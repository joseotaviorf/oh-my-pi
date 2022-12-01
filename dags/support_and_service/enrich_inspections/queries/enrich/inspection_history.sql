WITH assessment AS ( --There should only be a single assessment for an inspection, but there are some duplications that should be removed.
    SELECT
        a.id_inspection,
        a.id_assessment,
        a.source,
        a.ts_finished,
        a.ts_started,
        a.ts_created
    FROM
        datalake_inspections_clean.assessment AS a
    QUALIFY
        a.ts_updated = FIRST(a.ts_updated) OVER (PARTITION BY a.id_inspection ORDER BY a.ts_updated DESC)
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
union_inspection_history AS (
    SELECT
        i.id_inspection,
        i.id_external,
        i.id_schedule AS id_booking,
        i.id_contract,
        GET_JSON_OBJECT(i.house, '$.cityId') AS id_city,
        LOWER(GET_JSON_OBJECT(i.house, '$.city')) AS city_name,
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
        datalake_inspections_clean.inspection AS i
    UNION
    SELECT
        MD5(CONCAT(i.id, 'PWA')) AS id_inspection,
        i.id AS id_external,
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
inspection_reschedule AS (
  SELECT
    i.id_contract,
    i.inspection_type,
    COUNT(i.id_contract) AS total_rescheduling
  FROM
    union_inspection_history AS i
  GROUP BY 1,2
)
SELECT
    i.id_inspection,
    i.id_external,
    a.id_assessment,
    i.id_booking,
    i.id_contract,
    i.id_city,
    i.city_name,
    i.inspection_type,
    i.source,
    a.source AS assessment_source,
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
    a.ts_started AS ts_execution_started,
    a.ts_finished AS ts_execution_finished,
    COALESCE(a.ts_created, i.ts_inspected) AS ts_inspected,
    i.ts_created,
    i.ts_updated
FROM
    union_inspection_history AS i
LEFT JOIN
    assessment AS a
        ON a.id_inspection = i.id_inspection
LEFT JOIN
    inspection_reschedule AS ir
        ON ir.id_contract = i.id_contract
        AND ir.inspection_type = i.inspection_type