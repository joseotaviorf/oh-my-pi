WITH booking_status_ranked AS (
    SELECT
        bsc.id_booking,
        bsc.status,
        bsc.reason_enum,
        ROW_NUMBER() OVER (PARTITION BY bsc.id_booking, bsc.status ORDER BY bsc.id DESC) AS rn
    FROM
        datalake_ebdb_clean.booking_status_change AS bsc
),
booking_status AS (
    SELECT
        id_booking,
        status,
        reason_enum
    FROM
        booking_status_ranked
    WHERE
        rn = 1
),
status_log_ranked AS (
    SELECT
        id_schedule,
        id_author_user,
        ROW_NUMBER() OVER (PARTITION BY id_schedule ORDER BY ts_created) AS rn
    FROM
        datalake_ebdb_clean.visit_status_log
    WHERE
        event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED')
        AND ts_created >= '2024-08-01'
),
status_log AS (
    SELECT
        id_schedule,
        id_author_user
    FROM
        status_log_ranked
    WHERE
        rn = 1
),
first_booking_author_sc AS (
    SELECT DISTINCT
        bsc.id_booking,
        FIRST_VALUE(id_user) OVER (
          PARTITION BY bsc.id_booking ORDER BY id
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS id_user_creation
    FROM
        datalake_ebdb_clean.booking_status_change AS bsc
),
first_booking_author AS (
    SELECT DISTINCT
        b.id AS id_booking,
        COALESCE(sl.id_author_user, b.id_attendant, fbasc.id_user_creation) AS id_user_who_created
    FROM
        datalake_ebdb_clean.booking AS b
    LEFT JOIN
        status_log AS sl
            ON b.id = sl.id_schedule
    LEFT JOIN
        first_booking_author_sc AS fbasc
            ON b.id = fbasc.id_booking
),
min_canceled_date_ranked AS (
    SELECT
        b_aud.id AS id_booking,
        b_aud.rev AS rev_canceled,
        -- RANK, not ROW_NUMBER: the original MIN(rev) OVER (...) = rev kept every row
        -- tied on the lowest revision.
        RANK() OVER (PARTITION BY b_aud.id ORDER BY b_aud.rev ASC) AS rn
    FROM
        datalake_ebdb_clean.booking_aud AS b_aud
    WHERE
        b_aud.status = 'Cancelado'
        AND b_aud.mod_status = 1
),
min_canceled_date AS (
    SELECT
        id_booking,
        rev_canceled
    FROM
        min_canceled_date_ranked
    WHERE
        rn = 1
),
canceled_date AS (
    SELECT
        mcd.id_booking,
        ure.id_user AS id_user_who_canceled,
        -- TODO [ODS] check if milliseconds is really needed for this column
        CAST(FROM_UNIXTIME(ure.ts_revision/1000) AS TIMESTAMP)
          + (ure.ts_revision % 1000) * INTERVAL 1 MILLISECONDS
        AS ts_first_canceled
    FROM
        min_canceled_date AS mcd
    JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
          ON ure.id = mcd.rev_canceled
),
appointment_history_ranked AS (
    SELECT
        ah.*,
        ROW_NUMBER() OVER (PARTITION BY ah.id_appointment ORDER BY ah.ts_updated DESC) AS rn
    FROM
        datalake_schedules_clean.appointment_history AS ah
),
appointment_history AS (
    SELECT
        *
    FROM
        appointment_history_ranked
    WHERE
        rn = 1
),
creation_users_ranked AS (
    SELECT
        id_appointment,
        id_updated_by_reference AS id_user_who_created,
        ROW_NUMBER() OVER (PARTITION BY id_appointment ORDER BY ts_updated ASC) AS rn
    FROM
        datalake_schedules_clean.appointment_history
    WHERE
        status = 'WAITING_CONFIRMATION'
),
creation_users AS (
    SELECT
        id_appointment,
        id_user_who_created
    FROM
        creation_users_ranked
    WHERE
        rn = 1
),
canceled_users_ranked AS (
    SELECT
        id_appointment,
        id_updated_by_reference AS id_user_who_canceled,
        ROW_NUMBER() OVER (PARTITION BY id_appointment ORDER BY ts_updated ASC) AS rn
    FROM
        datalake_schedules_clean.appointment_history
    WHERE
        status = 'CANCELED'
),
canceled_users AS (
    SELECT
        id_appointment,
        id_user_who_canceled
    FROM
        canceled_users_ranked
    WHERE
        rn = 1
),
inspection_appointment_data AS (
    SELECT
        a.id_appointment AS id_is_appointment,
        a.id_external_appointment AS id_main_appointment,
        a.id_inspection,
        a.id_inspector,
        creation_users.id_user_who_created,
        canceled_users.id_user_who_canceled,
        s.type,
        a.status,
        ah.category_name AS status_made_by,
        ah.category_description AS status_description,
        a.cancellation_reason,
        a.observation,
        'IS' AS source,
        s.slot_of_day,
        s.duration_in_slots,
        a.is_fixed_agent,
        s.is_confirmed,
        a.dt_scheduled AS ts_appointment_inspected_local_tz,
        a.ts_created AS ts_appointment_created_utc,
        a.ts_updated AS ts_appointment_updated_utc,
        a.ts_created - INTERVAL 3 HOURS AS ts_appointment_created_local_tz,
        a.ts_updated - INTERVAL 3 HOURS AS ts_appointment_updated_local_tz,
        IF(a.status = "CANCELLED", FIRST(a.ts_updated) OVER (PARTITION BY a.id_inspection ORDER BY a.ts_updated), NULL) AS ts_first_appointment_cancelled_utc,
        IF(a.status = "CANCELLED", FIRST(a.ts_updated - INTERVAL 3 HOURS) OVER (PARTITION BY a.id_inspection ORDER BY a.ts_updated), NULL) AS ts_first_appointment_cancelled_local_tz,
        a.year,
        a.month,
        a.day
    FROM
        datalake_inspection_services_clean.appointment AS a
    LEFT JOIN
        datalake_ebdb_clean.booking AS b
          ON a.id_external_appointment = b.id
    LEFT JOIN
        datalake_schedules_clean.appointment AS s
          ON COALESCE(a.id_schedules, b.id_schedule) = s.id
    LEFT JOIN
        appointment_history AS ah
          ON b.id_schedule = ah.id_appointment
    LEFT JOIN
        creation_users
            ON a.id_appointment = creation_users.id_appointment
    LEFT JOIN
        canceled_users
            ON a.id_appointment = canceled_users.id_appointment
    WHERE
        DATE(a.ts_updated) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
main_appointment_data AS (
    SELECT
        a.id_appointment AS id_is_appointment,
        b.id AS id_main_appointment,
        MD5(CONCAT(i.id, 'PWA')) AS id_inspection,
        b.id_agent AS id_inspector,
        fba.id_user_who_created,
        cd.id_user_who_canceled,
        CASE
            WHEN LOWER(b.type) IN ('vistoria', 'vistoriaquarteirizada') THEN 'INSPECTION'
        END AS type,
        CASE
            WHEN LOWER(b.status) = 'agendado' THEN 'DONE'
            WHEN LOWER(b.status) = 'cancelado' THEN 'CANCELLED'
            WHEN LOWER(b.status) = 'marcado' THEN 'SCHEDULED'
            WHEN LOWER(b.status) = 'aguardandoconfirmacao' THEN 'WAITING_CONFIRMATION'
        END AS status,
        NULL AS status_made_by,
        NULL AS status_description,
        IF(b.status = 'Cancelado', bs.reason_enum, NULL) AS cancellation_reason,
        NULL AS observation,
        'PWA' AS source,
        b.slot_day AS slot_of_day,
        b.slots_duration AS duration_in_slots,
        b.is_agent_fixed AS is_fixed_agent,
        b.is_confirmed,
        CAST(b.dt_booking AS TIMESTAMP)
          + FLOOR((b.slot_day * 15 / 60)+8) * INTERVAL 1 HOURS
          + ABS(b.slot_day * 15 % 60) * INTERVAL 1 MINUTES
        AS ts_appointment_inspected_local_tz,
        b.ts_created AS ts_appointment_created_utc,
        b.ts_updated AS ts_appointment_updated_utc,
        b.ts_created - INTERVAL 3 HOUR AS ts_appointment_created_local_tz,
        b.ts_updated - INTERVAL 3 HOUR AS ts_appointment_updated_local_tz,
        cd.ts_first_canceled AS ts_first_appointment_cancelled_utc,
        cd.ts_first_canceled - INTERVAL 3 HOUR AS ts_first_appointment_cancelled_local_tz,
        YEAR(b.ts_updated) AS year,
        MONTH(b.ts_updated) AS month,
        DAY(b.ts_updated) AS day
    FROM
        datalake_ebdb_clean.booking AS b
    LEFT JOIN
        datalake_inspection_services_clean.appointment AS a
          ON b.id = a.id_external_appointment
    LEFT JOIN
        datalake_ebdb_clean.inspection AS i
          ON b.id = i.id_booking
    LEFT JOIN
        datalake_inspection_services_clean.inspection AS is
          ON i.id = is.id_external
    LEFT JOIN
        booking_status AS bs
          ON b.id = bs.id_booking
          AND b.status = bs.status
    LEFT JOIN
        canceled_date AS cd
          ON b.id = cd.id_booking
    LEFT JOIN
        first_booking_author AS fba
            ON b.id = fba.id_booking
    WHERE
        b.type IN ('Vistoria', 'VistoriaQuarteirizada')
        AND DATE(b.ts_updated) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
coalesce_appointment_sources AS (
    SELECT
        COALESCE(iad.id_is_appointment, md.id_is_appointment) AS id_is_appointment,
        COALESCE(iad.id_main_appointment, md.id_main_appointment) AS id_main_appointment,
        COALESCE(iad.id_inspection, md.id_inspection) AS id_inspection,
        COALESCE(iad.id_inspector, md.id_inspector) AS id_inspector,
        COALESCE(md.id_user_who_created, iad.id_user_who_created) AS id_user_who_created,
        COALESCE(md.id_user_who_canceled, iad.id_user_who_canceled) AS id_user_who_canceled,
        COALESCE(iad.type, md.type) AS type,
        COALESCE(iad.status, md.status) AS status,
        iad.status_made_by,
        iad.status_description,
        COALESCE(iad.cancellation_reason, md.cancellation_reason) AS cancellation_reason,
        iad.observation,
        COALESCE(iad.source, md.source) AS source,
        COALESCE(iad.slot_of_day, md.slot_of_day) AS slot_of_day,
        COALESCE(iad.duration_in_slots, md.duration_in_slots) AS duration_in_slots,
        COALESCE(iad.is_fixed_agent, md.is_fixed_agent) AS is_fixed_agent,
        COALESCE(iad.is_confirmed, md.is_confirmed) AS is_confirmed,
        COALESCE(iad.ts_appointment_inspected_local_tz, md.ts_appointment_inspected_local_tz) AS ts_appointment_inspected_local_tz,
        COALESCE(iad.ts_appointment_created_utc, md.ts_appointment_created_utc) AS ts_appointment_created_utc,
        COALESCE(iad.ts_appointment_updated_utc, md.ts_appointment_updated_utc) AS ts_appointment_updated_utc,
        COALESCE(iad.ts_appointment_created_local_tz, md.ts_appointment_created_local_tz) AS ts_appointment_created_local_tz,
        COALESCE(iad.ts_appointment_updated_local_tz, md.ts_appointment_updated_local_tz) AS ts_appointment_updated_local_tz,
        COALESCE(iad.ts_first_appointment_cancelled_utc, md.ts_first_appointment_cancelled_utc) AS ts_first_appointment_cancelled_utc,
        COALESCE(iad.ts_first_appointment_cancelled_local_tz, md.ts_first_appointment_cancelled_local_tz) AS ts_first_appointment_cancelled_local_tz,
        COALESCE(iad.year, md.year) AS year,
        COALESCE(iad.month, md.month) AS month,
        COALESCE(iad.day, md.day) AS day
    FROM
        inspection_appointment_data AS iad
    FULL OUTER JOIN
        main_appointment_data AS md
            -- md.id_is_appointment only exists for bookings joined to an IS appointment
            -- through id_external_appointment, which is the very column iad exposes as
            -- id_main_appointment. Matching on id_is_appointment therefore implies matching
            -- on id_main_appointment, and this single key covers both cases.
            ON iad.id_main_appointment = md.id_main_appointment
),
inspection_data_ranked AS (
    SELECT
        id_inspection,
        id_contract,
        type AS inspection_type,
        ts_updated,
        ROW_NUMBER() OVER (PARTITION BY id_inspection ORDER BY ts_updated DESC) AS rn
    FROM
        datalake_inspection_services_clean.inspection
),
inspection_data AS (
    SELECT
        id_inspection,
        id_contract,
        inspection_type,
        ts_updated
    FROM
        inspection_data_ranked
    WHERE
        rn = 1
),
appointment_inspection_ranked AS (
    SELECT
        MD5(COALESCE(CONCAT(cas.id_is_appointment, 'IS'), CONCAT(cas.id_main_appointment, 'PWA'))) AS id_appointment,
        cas.id_is_appointment,
        cas.id_main_appointment,
        cas.id_inspection,
        cas.id_inspector,
        cas.id_user_who_created,
        cas.id_user_who_canceled,
        cas.type,
        cas.status,
        cas.status_made_by,
        cas.status_description,
        cas.cancellation_reason,
        cas.observation,
        cas.source,
        cas.slot_of_day,
        cas.duration_in_slots,
        cas.is_fixed_agent,
        cas.is_confirmed,
        CASE
            WHEN FIRST(i.id_inspection) OVER (PARTITION BY i.id_contract, i.inspection_type ORDER BY i.ts_updated) == cas.id_inspection THEN TRUE
            ELSE FALSE
        END AS is_first_schedule,
        CASE
            -- This 194233 value, is the system user id to identify if it was an automatic schedule.
            WHEN cas.id_user_who_created = 194233 THEN TRUE
            ELSE FALSE
        END AS is_first_schedule_auto,
        CASE
            WHEN DATE(cas.ts_first_appointment_cancelled_utc) = DATE(TO_UTC_TIMESTAMP(cas.ts_appointment_inspected_local_tz, 'UTC')) THEN TRUE
            ELSE FALSE
        END AS is_d0_canceled,
        CASE
            WHEN DATE(cas.ts_first_appointment_cancelled_utc) = DATE_SUB(DATE(TO_UTC_TIMESTAMP(cas.ts_appointment_inspected_local_tz, 'UTC')), 1) THEN TRUE
            ELSE FALSE
        END AS is_d1_canceled,
        CASE
            WHEN cas.cancellation_reason NOT IN (
                    'INSPECTOR_BLOCKED_SCHEDULE',
                    'CANCELED_PROBLEM_INSPECTOR',
                    'CANCELED_INSPECTOR_NOT_ATTEND',
                    'CANCELED_INSPECTOR_CAN_NOT_ATTEND_INSPECTION'
                )
                THEN TRUE
            WHEN cas.cancellation_reason IS NULL THEN NULL
            ELSE FALSE
        END AS is_not_canceled_by_inspector,
        TO_UTC_TIMESTAMP(cas.ts_appointment_inspected_local_tz, 'UTC') AS ts_appointment_inspected_utc,
        cas.ts_appointment_inspected_local_tz,
        cas.ts_appointment_created_utc,
        cas.ts_appointment_updated_utc,
        cas.ts_appointment_created_local_tz,
        cas.ts_appointment_updated_local_tz,
        cas.ts_first_appointment_cancelled_utc,
        cas.ts_first_appointment_cancelled_local_tz,
        cas.year,
        cas.month,
        cas.day,
        ROW_NUMBER() OVER (
            PARTITION BY MD5(COALESCE(CONCAT(cas.id_is_appointment, 'IS'), CONCAT(cas.id_main_appointment, 'PWA')))
            ORDER BY cas.ts_appointment_updated_utc DESC
        ) AS rn
    FROM
        coalesce_appointment_sources AS cas
    LEFT JOIN
        inspection_data AS i
          ON cas.id_inspection = i.id_inspection
)
SELECT
    id_appointment,
    id_is_appointment,
    id_main_appointment,
    id_inspection,
    id_inspector,
    id_user_who_created,
    id_user_who_canceled,
    type,
    status,
    status_made_by,
    status_description,
    cancellation_reason,
    observation,
    source,
    slot_of_day,
    duration_in_slots,
    is_fixed_agent,
    is_confirmed,
    is_first_schedule,
    is_first_schedule_auto,
    is_d0_canceled,
    is_d1_canceled,
    is_not_canceled_by_inspector,
    ts_appointment_inspected_utc,
    ts_appointment_inspected_local_tz,
    ts_appointment_created_utc,
    ts_appointment_updated_utc,
    ts_appointment_created_local_tz,
    ts_appointment_updated_local_tz,
    ts_first_appointment_cancelled_utc,
    ts_first_appointment_cancelled_local_tz,
    year,
    month,
    day
FROM
    appointment_inspection_ranked
WHERE
    rn = 1
