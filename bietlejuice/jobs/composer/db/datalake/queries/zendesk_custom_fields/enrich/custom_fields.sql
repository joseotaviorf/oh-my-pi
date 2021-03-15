WITH tickets_filter AS (
    SELECT DISTINCT
        *
    FROM
        datalake_zendesk_tickets_clean.tickets t
    WHERE
        (
            t.ticket_via <> 'api'
            OR (
                t.ticket_via='api'
                AND t.tags NOT LIKE '%hsm%'
            )
        )
        AND t.year = '{year}'
        AND t.month = '{month}'
        AND t.day = '{day}'
),
last_updated_ticket AS (
    SELECT
        id_ticket,
        MAX(ts_updated) AS ts_last_updated
    FROM
        tickets_filter
    GROUP BY 1
),
distinct_tickets AS (
    SELECT
        tf.id_ticket,
        tf.custom_fields,
        tf.ts_updated,
        tf.dt_extracted
    FROM
        tickets_filter tf
    INNER JOIN
        last_updated_ticket lt
            ON tf.id_ticket = lt.id_ticket
            AND tf.ts_updated = lt.ts_last_updated
)
SELECT
    df.id_ticket,
    cf.id AS id_field,
    cf.value AS value_field,
    df.custom_fields,
    df.ts_updated,
    YEAR(dt_extracted) AS year,
    MONTH(dt_extracted) AS month,
    DAY(dt_extracted) AS day
FROM
    distinct_tickets df
LATERAL VIEW
    EXPLODE(FROM_JSON(df.custom_fields,'array<struct<id:string,value:string>>')) AS cf
WHERE
    cf.value IS NOT NULL
