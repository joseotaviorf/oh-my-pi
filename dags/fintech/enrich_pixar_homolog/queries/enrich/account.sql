WITH cte_most_recent AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_updated
    FROM
        datalake_pixar_clean.account
    GROUP BY 1
)
SELECT
    a.id,
    a.pix_key,
    a.requested_by,
    a.bank_name,
    a.bank_fee,
    a.ts_created,
    a.ts_updated,
    a.year,
    a.month,
    a.day
FROM
    datalake_pixar_clean.account a
RIGHT JOIN 
    cte_most_recent cte 
        ON cte.id = a.id
        AND cte.ts_updated = a.ts_updated
