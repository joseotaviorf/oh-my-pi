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
        COALESCE(a.id_external_appointment, i.id_schedule) AS id_booking,
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
    LEFT JOIN
        datalake_inspections_clean.appointment AS a
          ON i.id_inspection = a.id_inspection
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
)
SELECT DISTINCT
    i.id_inspection,
    i.id_previous_inspection,
    i.id_external,
    a.id_assessment,
    i.id_booking,
    ad.id_appointment,
    i.id_contract,
    i.id_client_side,
    i.id_house,
    i.id_inspector,
    ic.id_country,
    ic.id_city,
    ic.city_name,
    COALESCE(i.country_code, ic.country_code) AS country_code,
    c.default_timezone AS country_default_timezone,
    i.inspection_type,
    ad.type AS booking_type,
    i.source,
    a.source AS assessment_source,
    i.status,
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
        WHEN DATE(ad.ts_first_appointment_cancelled_utc) = DATE(ad.ts_appointment_inspected_utc) THEN True
        ELSE False
    END AS is_d0_canceled,
    CASE
        WHEN DATE(ad.ts_first_appointment_cancelled_utc) = DATE_SUB(DATE(ad.ts_appointment_inspected_utc), 1) THEN True
        ELSE False
    END AS is_d1_canceled,
    CASE
        WHEN ad.cancellation_reason NOT IN (
                'INSPECTOR_BLOCKED_SCHEDULE',
                'CANCELED_PROBLEM_INSPECTOR',
                'CANCELED_INSPECTOR_NOT_ATTEND',
                'CANCELED_INSPECTOR_CAN_NOT_ATTEND_INSPECTION'
            )
            THEN TRUE
        WHEN ad.cancellation_reason IS NULL THEN NULL
        ELSE FALSE
    END AS is_not_canceled_by_inspector,
    ic.dt_contract_entrance,
    ic.dt_contract_termination,
    ic.dt_execution_limit,
    ad.ts_appointment_inspected_utc AS ts_booking_inspected_utc,
    ad.ts_appointment_inspected_utc AS ts_booking_inspected_local_tz,
    ad.ts_appointment_created_utc AS ts_booking_created_utc,
    ad.ts_appointment_created_local_tz AS ts_booking_created_local_tz,
    ad.ts_first_appointment_cancelled_utc AS ts_booking_cancelled_utc,
    ad.ts_first_appointment_cancelled_local_tz AS ts_booking_cancelled_local_tz,
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
    i.ts_updated,
    YEAR(i.ts_updated) AS year,
    MONTH(i.ts_updated) AS month,
    DAY(i.ts_updated) AS day
FROM
    union_inspection_history AS i
LEFT JOIN
    datalake_inspections_clean.assessment AS a
        ON a.id_inspection = i.id_inspection
LEFT JOIN
    inspection_contract AS ic
        ON ic.id_contract = i.id_contract
        AND ic.inspection_type = i.inspection_type
LEFT JOIN
    datalake_ebdb_clean.country c
        ON c.id = ic.id_country
LEFT JOIN
    datalake_inspections.appointment_inspection AS ad
      ON ad.id_inspection = i.id_inspection
      OR ad.id_main_appointment = i.id_booking
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY i.id_inspection ORDER BY i.ts_updated DESC) = 1
