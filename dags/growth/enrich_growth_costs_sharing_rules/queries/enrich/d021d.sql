SELECT DISTINCT
    dd.sk_date AS id_date,
    '{id_rule}' AS id_rule,
    dr.city_group AS city_group,
    (DENSE_RANK() OVER(PARTITION BY dd.sk_date, dr.city_group ORDER BY fhs.sk_sale_listing) +
     DENSE_RANK() OVER(PARTITION BY dd.sk_date, dr.city_group ORDER BY fhs.sk_sale_listing DESC) - 1) /
         (DENSE_RANK() OVER(PARTITION BY dd.sk_date ORDER BY fhs.sk_sale_listing) +
         DENSE_RANK() OVER(PARTITION BY dd.sk_date ORDER BY fhs.sk_sale_listing DESC) - 1) AS share,
    'demand' AS funnel_side,
    CAST(NULL AS STRING) AS business_context
FROM
    dw_public.dim_date AS dd
JOIN dw_sale.fact_listing_status AS fhs
    ON dd.sk_date BETWEEN fhs.sk_status_start_date
        AND COALESCE(NULLIF(fhs.sk_status_end_date, -1), date_format(CURRENT_DATE - 1, 'yyyyMMdd'))
    AND fhs.status_history = 'PUBLISHED'
    AND fhs.sk_status_start_date != -1
JOIN dw_public.dim_region AS dr
    ON dr.sk_region = fhs.sk_region
    AND dr.city_group IS NOT NULL
WHERE
    city_group != 'Belo Horizonte'
    AND country_code = 'BR'