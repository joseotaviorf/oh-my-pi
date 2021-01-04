WITH distinct_dims AS (
    SELECT 
        CONCAT(FIRST(id_ad), campaign_name) AS sk_ad,
        ad_name,
        adset_name,
        campaign_name,
        acc AS account_name,
        is_test_campaign,
        year,
        month,
        day
    FROM 
        datalake_marketing_costs.facebook_insights
    WHERE
        year = {year} 
        AND month = {month} 
        AND day = {day}
    GROUP BY
        2,3,4,5,6,7,8,9
)

SELECT
    distinct_dims.*,
    NOW() AS ts_load
FROM 
    distinct_dims
LEFT JOIN 
    dw_marketing_costs_staging.dim_facebook_ad AS stg_dim
        ON distinct_dims.sk_ad = stg_dim.sk_ad
WHERE 
    stg_dim.sk_ad IS NULL
