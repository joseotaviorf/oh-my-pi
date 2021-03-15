SELECT DISTINCT
    t.id_ticket,
    REGEXP_REPLACE(t_tag, '\\"|\\[|\\]', '') AS ticket_tag,
    t.ts_updated,
    t.tags,
    YEAR(t.ts_updated) AS year,
    MONTH(t.ts_updated) AS month,
    DAY(t.ts_updated) AS day
FROM
    datalake_zendesk_tickets_clean.tickets t
LATERAL VIEW
    EXPLODE(SPLIT(t.tags, ',')) AS t_tag
WHERE
    (
        t.ticket_via <> 'api'
        OR (
            t.ticket_via = 'api'
            AND t.tags NOT LIKE '%hsm%'
        )
    )
    AND t.year = '{year}'
    AND t.month = '{month}'
    AND t.day = '{day}'
