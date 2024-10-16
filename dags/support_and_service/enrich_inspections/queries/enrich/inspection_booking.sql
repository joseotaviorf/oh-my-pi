WITH union_inspection_history AS (
    WITH last_inspection_update AS (
        SELECT
            *
        FROM
            datalake_inspections_clean.inspection_aud AS ia
        QUALIFY
            ia.ts_updated = FIRST(ia.ts_updated) OVER (PARTITION BY ia.id_inspection ORDER BY ia.ts_updated DESC)
    )
    SELECT
        i.id_inspection,
        i.id_previous_inspection,
        i.id_external,
        i.id_inspector,
        NULL AS id_booking,
        NULL AS id_appointment,
        i.id_contract,
        i.id_client_side,
        GET_JSON_OBJECT(i.house, '$.id') AS id_house,
        GET_JSON_OBJECT(i.house, '$.cityId') AS id_city,
        LOWER(GET_JSON_OBJECT(i.house, '$.city')) AS city_name,
        GET_JSON_OBJECT(i.house, '$.countryCode') AS country_code,
        i.type AS inspection_type,
        'IS' AS source,
        i.status,
        CASE
            WHEN GET_JSON_OBJECT(i.schedule, '$.observation') = "Local das chaves: Proprietário acompanha" THEN True
            ELSE FALSE
        END AS has_owner_accompanying,
        NULL AS ts_inspected,
        i.ts_created,
        i.ts_updated,
        NULL AS ts_first_synced
    FROM
        last_inspection_update AS i
    WHERE
        DATE(i.ts_updated) BETWEEN '{load_start_date}' AND '{load_end_date}'
    UNION
    SELECT
        i.id_inspection,
        NULL AS id_previous_inspection,
        i.id_external,
        i.id_inspector,
        i.id_booking,
        i.id_appointment,
        i.id_contract,
        NULL AS id_client_side,
        i.id_house,
        NULL AS id_city,
        NULL AS city_name,
        NULL AS country_code,
        i.inspection_type,
        "PWA" AS source,
        i.status,
        NULL AS has_owner_accompanying,
        i.ts_inspected,
        i.ts_created,
        i.ts_updated,
        i.ts_first_synced
    FROM
        datalake_inspections.main_inspection_booking AS i
    WHERE
        DATE(i.ts_updated) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
appointment_data AS (
    SELECT
        *,
        dt_scheduled AS ts_booking_inspected_utc,
        dt_scheduled - INTERVAL 3 HOURS AS ts_booking_inspected_local_tz,
        ts_created AS ts_booking_created_utc,
        ts_created - INTERVAL 3 HOURS AS ts_booking_created_local_tz,
        IF(status = "CANCELLED", FIRST(ts_updated) OVER (PARTITION BY id_inspection ORDER BY ts_updated), NULL) AS ts_booking_cancelled_utc,
        IF(status = "CANCELLED", FIRST(ts_updated - INTERVAL 3 HOURS) OVER (PARTITION BY id_inspection ORDER BY ts_updated), NULL) AS ts_booking_cancelled_local_tz
    FROM
        datalake_inspections_clean.appointment
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_inspection ORDER BY ts_updated DESC) = 1
),
inspection_contract AS (
    SELECT
        c.id AS id_contract,
        i.inspection_type,
        r.id_country,
        r.country_code,
        MAX(COALESCE(r.id_city, i.id_city)) AS id_city,
        MAX(COALESCE(r.city_name, i.city_name)) AS city_name,
        COUNT(i.id_contract) AS total_rescheduling,
        CASE
            WHEN i.inspection_type = "offboarding" THEN MAX(t.dt_termination)
            WHEN i.inspection_type = "onboarding" THEN c.dt_entered
        END AS dt_execution_limit,
        c.dt_entered AS dt_contract_entrance,
        MAX(t.dt_termination) AS dt_contract_termination,
        MAX(t.ts_canceled) AS ts_termination_canceled
    FROM
        union_inspection_history AS i
    JOIN
        datalake_ebdb_contract.contract AS c
            ON c.id = i.id_contract
    LEFT JOIN
        datalake_terminator_clean.termination AS t
            ON t.id_contract = c.id
    LEFT JOIN
        datalake_ebdb_clean.house AS h
            ON c.id_house = h.id
    LEFT JOIN
        datalake_region.region AS r
            ON r.id = h.id_region
    GROUP BY 1, 2, 3, 4, 9
),
repairs AS (
    SELECT
        ins.id_inspection,
        ins.id_contract,
        rr.id_repair_request,
        rr.ts_created AS dt_repair,
        rev1.reviewer_type AS requester_type,
        rev2.reviewer_type AS granted_type,
        rr.responsibility,
        rr.comment,
        rr.is_finished,
        rr.is_exempted,
        rev2.reviewer_type = 'OWNER' AS is_exempted_by_owner,
        CASE
          WHEN rr.is_finished = false AND rev2.reviewer_type = 'ADMIN' AND rr.is_exempted = true THEN true
          ELSE false
        END AS exempted_on_ar,
        ROW_NUMBER() OVER (PARTITION BY id_repair_request ORDER BY rr.ts_updated DESC) AS rn
    FROM
        datalake_inspections_clean.repair_request AS rr
    LEFT JOIN
        datalake_inspections_clean.item_group AS ig
          ON rr.id_item_group = ig.id_item_group
    LEFT JOIN
        datalake_inspections_clean.room AS ro
          ON ro.id_room = ig.id_room
    LEFT JOIN
        datalake_inspections_clean.assessment AS asm
          ON asm.id_assessment = ro.id_assessment
    LEFT JOIN
        datalake_inspections_clean.inspection AS ins
          ON ins.id_inspection = asm.id_inspection
    LEFT JOIN
        datalake_inspections_clean.reviewer AS rev1
          ON rev1.id_reviewer = rr.id_reviewer
    LEFT JOIN
        datalake_inspections_clean.reviewer AS rev2
          ON rev2.id_reviewer = rr.id_granted_by
),
repair_metrics AS (
    SELECT
        id_contract,
        id_inspection,
        COUNT(CASE
          WHEN exempted_on_ar = false AND requester_type IN ('ADMIN','INSPECTIONS_SERVICE') THEN 1
        END) AS total_tentant_repair_ar,
        COUNT(CASE
          WHEN requester_type = 'OWNER' THEN 1
        END) AS repairs_added_by_owner_review,
        COUNT(CASE
          WHEN is_exempted_by_owner = true THEN 1
        END) AS repairs_exempted_by_owner_review,
        COUNT(CASE
          WHEN exempted_on_ar = false AND requester_type IN ('ADMIN','INSPECTIONS_SERVICE') THEN 1
        END) +
          COUNT(CASE
            WHEN requester_type = 'OWNER' THEN 1
          END) -
            COUNT(CASE
              WHEN is_exempted_by_owner = true THEN 1
            END) AS total_tentant_repair_review,
        COUNT(CASE
          WHEN is_finished = true AND is_exempted = true THEN 1
        END) AS repairs_exempted_ac,
        COUNT(
          CASE
            WHEN responsibility = 'ABSORBED_BY_COMPANY' AND is_exempted_by_owner = false THEN 1
        END) AS repairs_absorbed_ac,
        COUNT(
          CASE
            WHEN exempted_on_ar = false AND requester_type IN ('ADMIN','INSPECTIONS_SERVICE') THEN 1
        END) +
            COUNT(CASE
              WHEN requester_type = 'OWNER' THEN 1
            END) -
              COUNT(CASE
                WHEN is_exempted_by_owner = true THEN 1
              END) -
                COUNT(
                  CASE
                    WHEN is_finished = true AND is_exempted = true THEN 1
                END) -
                  COUNT(CASE
                    WHEN responsibility = 'ABSORBED_BY_COMPANY' AND is_exempted_by_owner = false THEN 1
                  END) AS total_tentant_repair_ac
    FROM
        repairs
    WHERE
        comment IS NOT NULL
        AND responsibility IN ('TENANT', 'OWNER', 'ABSORBED_BY_COMPANY', 'EXEMPTED')
        AND rn = 1
    GROUP BY
          1,2
)
SELECT DISTINCT
    i.id_inspection,
    i.id_previous_inspection,
    i.id_external,
    a.id_assessment,
    i.id_booking,
    COALESCE(MD5(CONCAT(ad.id_appointment, 'IS')), i.id_appointment) AS id_appointment,
    i.id_contract,
    i.id_client_side,
    i.id_house,
    i.id_inspector,
    COALESCE(b.id_country, ic.id_country) AS id_country,
    ic.id_city,
    ic.city_name,
    COALESCE(i.country_code, b.country_code, ic.country_code) AS country_code,
    c.default_timezone AS country_default_timezone,
    i.inspection_type,
    b.type AS booking_type,
    i.source,
    a.source AS assessment_source,
    i.status,
    rm.total_tentant_repair_ar,
    rm.repairs_added_by_owner_review,
    rm.repairs_exempted_by_owner_review,
    rm.total_tentant_repair_review,
    rm.repairs_exempted_ac,
    rm.repairs_absorbed_ac,
    rm.total_tentant_repair_ac,
    i.has_owner_accompanying,
    CASE
        WHEN FIRST(i.id_inspection) OVER(PARTITION BY i.id_contract, i.inspection_type ORDER BY i.ts_created) == i.id_inspection THEN TRUE
        ELSE FALSE
    END AS is_first_schedule,
    CASE
        WHEN ic.total_rescheduling = 1
            AND (
                i.status = 'received'
                OR (i.status IN ('reviewed','Comentada', 'Finalizada') AND i.source = 'PWA')
            )
            THEN TRUE
        ELSE FALSE
    END AS is_executed_in_first_schedule,
    CASE
        WHEN DATE(COALESCE(b.ts_first_canceled_unevaluated, ad.ts_booking_cancelled_utc)) = DATE(COALESCE(b.ts_booking_utc, ad.ts_booking_inspected_utc)) THEN True
        ELSE False
    END AS is_d0_canceled,
    CASE
        WHEN DATE(COALESCE(b.ts_first_canceled_unevaluated, ad.ts_booking_cancelled_utc)) = DATE_SUB(DATE(COALESCE(b.ts_booking_utc, ad.ts_booking_inspected_utc)), 1) THEN True
        ELSE False
    END AS is_d1_canceled,
    CASE
        WHEN COALESCE(b.cancellation_reason, ad.cancellation_reason) NOT IN (
                'INSPECTOR_BLOCKED_SCHEDULE',
                'CANCELED_PROBLEM_INSPECTOR',
                'CANCELED_INSPECTOR_NOT_ATTEND',
                'CANCELED_INSPECTOR_CAN_NOT_ATTEND_INSPECTION'
            )
            THEN TRUE
        WHEN COALESCE(b.cancellation_reason, ad.cancellation_reason) IS NULL THEN NULL
        ELSE FALSE
    END AS is_not_canceled_by_inspector,
    ic.dt_contract_entrance,
    ic.dt_contract_termination,
    ic.dt_execution_limit,
    COALESCE(b.ts_booking_utc, ad.ts_booking_inspected_utc) AS ts_booking_inspected_utc,
    COALESCE(b.ts_booking_local_tz, ad.ts_booking_inspected_local_tz) AS ts_booking_inspected_local_tz,
    COALESCE(b.ts_created, ad.ts_booking_created_utc) AS ts_booking_created_utc,
    COALESCE(b.ts_created_local_tz, ad.ts_booking_created_local_tz) AS ts_booking_created_local_tz,
    COALESCE(b.ts_first_canceled_unevaluated, ad.ts_booking_cancelled_utc) AS ts_booking_cancelled_utc,
    COALESCE(b.ts_first_canceled_unevaluated_local_tz, ad.ts_booking_cancelled_local_tz) AS ts_booking_cancelled_local_tz,
    ic.ts_termination_canceled,
    a.ts_started AS ts_execution_started_local_tz,
    a.ts_finished AS ts_execution_finished_local_tz,
    COALESCE(
        TO_UTC_TIMESTAMP(a.ts_finished, c.default_timezone),
        i.ts_inspected
    ) AS ts_inspected,
    CASE
        WHEN i.source = "PWA" THEN i.ts_first_synced
        ELSE a.ts_created
    END AS ts_synced,
    i.ts_created,
    i.ts_updated
FROM
    union_inspection_history AS i
LEFT JOIN
    datalake_inspections_clean.assessment AS a
        ON a.id_inspection = i.id_inspection
LEFT JOIN
    datalake_booking.booking AS b
        ON i.id_booking = b.id
LEFT JOIN
    inspection_contract AS ic
        ON ic.id_contract = i.id_contract
        AND ic.inspection_type = i.inspection_type
LEFT JOIN
    datalake_ebdb_clean.country c
        ON c.id = COALESCE(b.id_country, ic.id_country)
LEFT JOIN
    appointment_data AS ad
      ON ad.id_inspection = i.id_inspection
LEFT JOIN
    repair_metrics AS rm
      ON rm.id_inspection = i.id_inspection
