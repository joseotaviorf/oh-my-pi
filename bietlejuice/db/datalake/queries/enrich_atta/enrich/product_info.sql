WITH cte_most_recent AS (
    SELECT
        id_product,
        MAX(ts_registration) AS ts_registration
    FROM
        datalake_atta_clean.product_info
    GROUP BY 1
)
SELECT
    pi.id_product,
    pi.product_name,
    pi.profile_doc,
    pi.is_active,
    pi.ts_registration,
    pi.year,
    pi.month,
    pi.day
FROM
    datalake_atta_clean.product_info AS pi
RIGHT JOIN
    cte_most_recent AS cte
        ON cte.id_product = pi.id_product
        AND cte.ts_registration = pi.ts_registration
