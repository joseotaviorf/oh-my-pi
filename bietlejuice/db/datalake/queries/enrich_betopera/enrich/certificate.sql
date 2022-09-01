WITH cte_most_recent AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_updated
    FROM
        datalake_betopera_clean.certificate
    GROUP BY 1
)
SELECT
    c.id,
    c.id_insurance,
    c.id_certificate_request,
    c.version,
    c.status,
    c.response_payload,
    c.file_url,
    c.dt_start,
    c.dt_end,
    c.dt_cancel,
    c.ts_created,
    c.ts_updated,
    c.year,
    c.month,
    c.day
FROM
    datalake_betopera_clean.certificate AS c
RIGHT JOIN
    cte_most_recent AS cte
        ON cte.id = c.id
        AND cte.ts_updated = c.ts_updated
