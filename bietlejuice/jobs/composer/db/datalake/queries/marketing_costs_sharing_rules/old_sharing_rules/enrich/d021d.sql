SELECT DISTINCT
    dd.sk_date::INTEGER AS  id_date,
    dr.city_group::VARCHAR AS city_group,
    (DENSE_RANK() OVER(PARTITION BY dd.sk_date, dr.city_group ORDER BY fhs.sk_sale_listing) +
     DENSE_RANK() OVER(PARTITION BY dd.sk_date, dr.city_group ORDER BY fhs.sk_sale_listing DESC) - 1) /
         (DENSE_RANK() OVER(PARTITION BY dd.sk_date ORDER BY fhs.sk_sale_listing) +
         DENSE_RANK() OVER(PARTITION BY dd.sk_date ORDER BY fhs.sk_sale_listing DESC) - 1)::FLOAT AS share,
    'demand' AS funnel_side
FROM
    dim_date AS dd
    JOIN sale.fact_listing_status AS fhs
        ON dd.sk_date BETWEEN fhs.sk_status_start_date
                                AND COALESCE(NULLIF(fhs.sk_status_end_date, -1), TO_CHAR(CURRENT_DATE - 1, 'YYYYMMDD')::BIGINT)
        AND fhs.status_history = 'PUBLISHED'
        AND fhs.sk_status_start_date != -1
    JOIN dim_region AS dr
        ON dr.sk_region = fhs.sk_region
        AND dr.city_group IS NOT NULL
WHERE
    city_group != 'Belo Horizonte'