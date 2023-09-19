WITH assessment AS ( --There should only be a single assessment for an inspection, but there are some duplications that should be removed.
    SELECT DISTINCT
        a.id_inspection,
        a.id_assessment,
        a.source,
        a.ts_finished,
        a.ts_started,
        a.ts_created
    FROM
        datalake_inspections_clean.assessment AS a
    QUALIFY
        a.ts_created = FIRST(a.ts_created) OVER (PARTITION BY a.id_inspection ORDER BY a.ts_created DESC)
),
main_inspection_aud_sync as(
    SELECT DISTINCT
        ia.id_inspection,
        FIRST_VALUE(ia.ts_last_synced) OVER (PARTITION BY ia.id_inspection, status ORDER BY ia.ts_last_synced ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS ts_first_synced
    FROM
        datalake_ebdb_clean.inspection_aud ia
    WHERE
        ia.status = 'Revisada'
),
union_inspection_history AS (
    WITH last_inspection_update AS (
        SELECT
            *
        FROM
            datalake_inspections_clean.inspection_aud AS ia
        QUALIFY
            ia.ts_updated = FIRST(ia.ts_updated) OVER (PARTITION BY ia.id_inspection ORDER BY ia.ts_updated DESC)
    ),
    main_exception AS (
        SELECT
            DISTINCT i.id AS id_inspection
        FROM
            datalake_ebdb_clean.inspection i
        EXCEPT
        SELECT
            DISTINCT i.id_external AS id_inspection
        FROM
            last_inspection_update AS i
    )
    SELECT
        i.id_inspection,
        i.id_previous_inspection,
        i.id_external,
        i.id_inspector,
        i.id_schedule AS id_booking,
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
        i.ts_updated
    FROM
        last_inspection_update AS i
    UNION
    SELECT
        MD5(CONCAT(i.id, 'PWA')) AS id_inspection,
        NULL AS id_previous_inspection,
        i.id AS id_external,
        i.id_user_inspector AS id_inspector,
        i.id_booking,
        i.id_contract,
        NULL AS id_client_side,
        i.id_house,
        NULL AS id_city,
        NULL AS city_name,
        NULL AS country_code,
        CASE
            WHEN i.type = 'Entrada' THEN 'onboarding'
            WHEN i.type = 'Saida' THEN 'offboarding'
            WHEN i.type = 'Constatacao' THEN 'verification'
            WHEN i.type = 'Portabilidade' THEN 'portability'
            ELSE NULL
        END inspection_type,
        "PWA" AS source,
        CASE
            WHEN i.status = 'Agendada' THEN 'scheduled'
            WHEN i.status = 'Cancelada' THEN 'cancelled'
            WHEN i.status IN ('Revisada' , 'EmRevisao') THEN 'reviewed'
            ELSE i.status
        END AS status,
        NULL AS has_owner_accompanying,
        TIMESTAMP(i.dt_inspected) AS ts_inspected,
        i.ts_created,
        i.ts_updated
    FROM
        main_exception AS me
    JOIN
        datalake_ebdb_clean.inspection AS i
            ON me.id_inspection = i.id
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
SELECT
    i.id_inspection,
    i.id_previous_inspection,
    i.id_external,
    a.id_assessment,
    i.id_booking,
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
        WHEN DATE(b.ts_first_canceled_unevaluated) = DATE(b.ts_booking_utc) THEN True
        ELSE False
    END AS is_d0_canceled,
    CASE
        WHEN DATE(b.ts_first_canceled_unevaluated) = DATE_SUB(DATE(b.ts_booking_utc), 1) THEN True
        ELSE False
    END AS is_d1_canceled,
    CASE
        WHEN b.cancellation_reason NOT IN (
                'INSPECTOR_BLOCKED_SCHEDULE',
                'CANCELED_PROBLEM_INSPECTOR',
                'CANCELED_INSPECTOR_NOT_ATTEND',
                'CANCELED_INSPECTOR_CAN_NOT_ATTEND_INSPECTION'
            )
            THEN TRUE
        WHEN b.cancellation_reason IS NULL THEN NULL
        ELSE FALSE
    END AS is_not_canceled_by_inspector,
    ic.dt_contract_entrance,
    ic.dt_contract_termination,
    ic.dt_execution_limit,
    b.ts_booking_utc AS ts_booking_inspected_utc,
    b.ts_booking_local_tz AS ts_booking_inspected_local_tz,
    b.ts_created AS ts_booking_created_utc,
    b.ts_created_local_tz AS ts_booking_created_local_tz,
    b.ts_first_canceled_unevaluated AS ts_booking_cancelled_utc,
    b.ts_first_canceled_unevaluated_local_tz AS ts_booking_cancelled_local_tz,
    ic.ts_termination_canceled,
    a.ts_started AS ts_execution_started_local_tz,
    a.ts_finished AS ts_execution_finished_local_tz,
    COALESCE(
        TO_UTC_TIMESTAMP(a.ts_finished, c.default_timezone),
        i.ts_inspected
    ) AS ts_inspected,
    CASE
        WHEN i.source = "PWA" THEN mias.ts_first_synced
        ELSE a.ts_created
    END AS ts_synced,
    i.ts_created,
    i.ts_updated
FROM
    union_inspection_history AS i
LEFT JOIN
    assessment AS a
        ON a.id_inspection = i.id_inspection
LEFT JOIN
    main_inspection_aud_sync AS mias
        ON mias.id_inspection = i.id_external
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