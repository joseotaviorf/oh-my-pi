WITH distinct_groups AS (
    SELECT DISTINCT
        g.id_group,
        g.name
    FROM
        datalake_zendesk_tickets_clean.groups AS g
    WHERE
        LOWER(g.name) LIKE "%reparo%"
),
custom_fields_filter AS (
  SELECT
        t.id_ticket,
        CONCAT('{{"custom_fields": ', REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(custom_fields, '"(?!")', ''), 'id:', '"id":"'), ',value:', '", "value":"'), '}', '"}'), '}}') AS custom_field,
        t.ts_updated,
        t.year,
        t.month,
        t.day
    FROM
        datalake_zendesk_tickets_clean.tickets_history AS t
    JOIN
        distinct_groups AS g
            ON t.id_group = g.id_group
    WHERE
        t.year = {year}
        AND t.month = {month}
        AND t.day = {day}
),
custom_fields AS (
    SELECT
        id_ticket,
        INLINE(
            FROM_JSON(
                custom_field: custom_fields[*],
                'ARRAY<STRUCT<id STRING, value STRING>>'
            )
        ),
        ts_updated,
        year,
        month,
        day
    FROM
        custom_fields_filter
)
SELECT
    cf.id_ticket,
    CAST(FIRST(cf.value) FILTER(WHERE cf.id = 114096515211) AS BIGINT) AS id_contract,
    MAP_FROM_ARRAYS(COLLECT_LIST(cf.id), COLLECT_LIST(cf.value)) AS custom_fields,
    FIRST(cf.value) FILTER(WHERE cf.id IN (46785608, 6314265356813, 360032588792)) AS client_type,
    FIRST(cf.value) FILTER(WHERE cf.id = 10479892278541) AS new_criticality,
    FIRST(cf.value) FILTER(WHERE cf.id = 10479805451021) AS criticality,
    FIRST(cf.value) FILTER(WHERE cf.id = 360047178772) AS service_rating_tags,
    TO_TIMESTAMP(FIRST(cf.value) FILTER(WHERE cf.id = 14216500749837), "dd/MM/yy HH:mm") AS ts_first_manual_fup_performed,
    TO_TIMESTAMP(FIRST(cf.value) FILTER(WHERE cf.id IN (10483353873549, 10483321522829)), "dd/MM/yy HH:mm") AS ts_provider_definition,
    TO_TIMESTAMP(FIRST(cf.value) FILTER(WHERE cf.id = 14216477864717), "dd/MM/yy HH:mm") AS ts_first_reply,
    cf.ts_updated,
    cf.year,
    cf.month,
    cf.day
FROM
    custom_fields cf
WHERE
    cf.value <> "null"
GROUP BY 1, 11, 12, 13, 14