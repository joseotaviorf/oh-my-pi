WITH cte_most_recent AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_updated
    FROM
        datalake_betopera_clean.certificate_request
    GROUP BY 1
)
SELECT
    cr.id,
    cr.id_insurance,
    cr.version,
    cr.payload,
    cr.status,
    cr.ts_synced,
    cr.ts_created,
    cr.ts_updated,
    cr.year,
    cr.month,
    cr.day
FROM
    datalake_betopera_clean.certificate_request AS cr
RIGHT JOIN
    cte_most_recent AS cte
        ON cte.id = cr.id
        AND cte.ts_updated = cr.ts_updated
