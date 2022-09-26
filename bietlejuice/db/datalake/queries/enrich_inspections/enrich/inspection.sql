WITH assessment AS ( --There should only be a single assessment for an inspection, but there are some duplications that should be removed.
    SELECT
        a.id_inspection,
        FIRST(a.id_assessment) OVER (PARTITION BY a.id_inspection ORDER BY a.ts_created DESC) AS id_assessment,
        FIRST(a.source) OVER (PARTITION BY a.id_inspection ORDER BY a.ts_created DESC) AS source,
        FIRST(a.ts_finished) OVER (PARTITION BY a.id_inspection ORDER BY a.ts_created DESC) AS ts_finished,
        FIRST(a.ts_started) OVER (PARTITION BY a.id_inspection ORDER BY a.ts_created DESC) AS ts_started
    FROM
        datalake_inspections_clean.assessment AS a
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
        datalake_inspections_clean.inspection AS i
),
inspections_union_historical AS (
    SELECT DISTINCT
        i.id_inspection,
        i.id_external,
        a.id_assessment,
        i.id_schedule AS id_booking,
        i.id_contract,
        GET_JSON_OBJECT(i.house, '$.cityId') AS id_city,
        LOWER(GET_JSON_OBJECT(i.house, '$.city')) AS city_name,
        i.type AS inspection_type,
        'IS' AS source,
        a.source AS assessment_source,
        i.status,
        CASE
            WHEN GET_JSON_OBJECT(i.schedule, '$.observation') = "Local das chaves: Proprietário acompanha" THEN True
            ELSE FALSE
        END AS has_owner_accompanying,
        a.ts_started,
        a.ts_finished,
        i.ts_created,
        i.ts_updated
    FROM
        datalake_inspections_clean.inspection AS i
    LEFT JOIN
        assessment AS a
            ON a.id_inspection = i.id_inspection
    UNION
    SELECT
        MD5(CONCAT(i.id, 'PWA')) AS id_inspection,
        i.id AS id_external,
        NULL AS id_assessment,
        i.id_booking,
        i.id_contract,
        NULL AS id_city,
        NULL AS city_name,
        CASE
            WHEN i.type = 'Entrada' THEN 'onboarding'
            WHEN i.type = 'Saida' THEN 'offboarding'
            WHEN i.type = 'Constatacao' THEN 'verification'
            WHEN i.type = 'Portabilidade' THEN 'portability'
            ELSE NULL
        END inspection_type,
        "PWA" AS source,
        NULL AS assessment_source,
        CASE
            WHEN i.status = 'Agendada' THEN 'scheduled'
            WHEN i.status = 'Cancelada' THEN 'cancelled'
            WHEN i.status IN ('Revisada' , 'EmRevisao') THEN 'reviewed'
            ELSE i.status
        END AS status,
        NULL AS has_owner_accompanying,
        NULL AS ts_started,
        i.dt_inspected AS ts_finished,
        i.ts_created,
        i.ts_updated
    FROM
        main_exception AS me
    JOIN
        datalake_ebdb_clean.inspection AS i
            ON me.id_inspection = i.id
),
contract_termination AS (
    SELECT
        ct.id_contract,
        FIRST(ct.id_region) OVER (PARTITION BY ct.id_contract ORDER BY ct.ts_created DESC) AS id_region,
        FIRST(ct.dt_contract_entrance) OVER (PARTITION BY ct.id_contract ORDER BY ct.ts_created DESC) AS dt_contract_entrance,
        FIRST(ct.dt_termination) OVER (PARTITION BY ct.id_contract ORDER BY ct.ts_created DESC) AS dt_contract_termination,
        FIRST(ct.ts_canceled) OVER (PARTITION BY ct.id_contract ORDER BY ct.ts_created DESC) AS ts_termination_canceled
    FROM
        datalake_offboarding.contract_termination AS ct
),
inspection_reschedule AS (
  SELECT
    i.id_contract,
    i.inspection_type,
    COUNT(i.id_contract) AS total_rescheduling
  FROM
    inspections_union_historical AS i
  GROUP BY 1,2
)
SELECT DISTINCT
    i.id_inspection,
    i.id_external,
    i.id_assessment,
    i.id_booking,
    i.id_contract,
    b.id_country,
    COALESCE(r.id_city, i.id_city) AS id_city,
    COALESCE(r.city_name, i.city_name) AS city_name,
    b.country_code,
    i.inspection_type,
    b.type AS booking_type,
    i.source,
    i.assessment_source,
    i.status,
    i.has_owner_accompanying,
    CASE
        WHEN FIRST(i.id_inspection) OVER(PARTITION BY i.id_contract, i.inspection_type ORDER BY i.ts_created) == i.id_inspection THEN TRUE
        ELSE FALSE
    END AS is_first_schedule,
    CASE
        WHEN ir.total_rescheduling = 1
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
    ct.dt_contract_entrance,
    ct.dt_contract_termination,
    CASE
      WHEN i.inspection_type = "offboarding" THEN ct.dt_contract_termination
      WHEN i.inspection_type = "onboarding" THEN ct.dt_contract_entrance
    END AS dt_execution_limit,
    b.ts_booking_utc AS ts_booking_inspected_utc,
    b.ts_booking_local_tz AS ts_booking_inspected_local_tz,
    b.ts_first_canceled_unevaluated AS ts_booking_cancelled_utc,
    b.ts_first_canceled_unevaluated_local_tz AS ts_booking_cancelled_local_tz,
    ct.ts_termination_canceled,
    i.ts_started,
    i.ts_finished,
    i.ts_created,
    i.ts_updated
FROM
    inspections_union_historical AS i
LEFT JOIN
    inspection_reschedule AS ir
        ON ir.id_contract = i.id_contract
        AND ir.inspection_type = i.inspection_type
LEFT JOIN
    datalake_booking.booking AS b
        ON i.id_booking = b.id
LEFT JOIN
    contract_termination AS ct
        ON ct.id_contract = i.id_contract
LEFT JOIN
    datalake_region.region AS r
        ON r.id = ct.id_region
