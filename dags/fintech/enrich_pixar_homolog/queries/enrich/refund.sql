WITH cte_most_recent AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_updated
    FROM
        datalake_pixar_clean.refund
    GROUP BY 1
)
SELECT
    r.id,
    r.id_charge,
    r.amount,
    r.status,
    r.ts_created,
    r.ts_updated,
    r.year,
    r.month,
    r.day
FROM
    datalake_pixar_clean.refund r
RIGHT JOIN 
    cte_most_recent cte 
        ON cte.id = r.id
        AND cte.ts_updated = r.ts_updated
