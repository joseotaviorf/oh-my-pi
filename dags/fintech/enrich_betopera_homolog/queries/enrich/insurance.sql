WITH cte_most_recent AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_updated
    FROM
        datalake_betopera_clean.insurance
    GROUP BY 1
)
SELECT
    i.id,
    i.id_idempotency ,
    i.source_type_code,
    i.status,
    i.version,
    i.ts_created,
    i.ts_updated,
    i.year,
    i.month,
    i.day
FROM
    datalake_betopera_clean.insurance AS i
RIGHT JOIN
    cte_most_recent AS cte
        ON cte.id = i.id
        AND cte.ts_updated = i.ts_updated
