WITH 
db_unpublished AS (
    SELECT 
        DATE_TRUNC('MONTH', ts_status_started) AS dt_month_status_started,
        DATE(ts_status_started) AS dt_status_started,
        ldi.country_code,
        CASE
            WHEN dhl.rent < 1500 THEN 'LOW'
            WHEN dhl.rent < 2500 THEN 'MEDIUM'
            ELSE 'HIGH'
        END AS value_segment,
        id_house_listing,
        ROW_NUMBER() OVER (PARTITION BY ldi.id_house, status_history ORDER BY  ts_status_started ) AS rn
    FROM 
        datalake_rental_historical_follow_up.house_listings_daily_info AS ldi
     LEFT JOIN 
       dw_rent.dim_house_listing AS dhl 
            ON ldi.id_house_listing = dhl.sk_house_listing    
    WHERE  
        status_history = 'UNPUBLISHED'
        AND ((YEAR = 2023 AND MONTH >= 10) OR (YEAR > 2023))
        AND ts_status_started >= DATE('2023-10-09')
        AND ts_status_started < DATE_TRUNC('MONTH', CURRENT_DATE) 
        AND dhl.listing_category_start = 'Re-Listing'
),
db_published AS (
    SELECT 
        DATE_TRUNC('MONTH', ts_status_started) AS dt_month_status_started,
        DATE(ts_status_started) AS dt_status_started,
        ldi.country_code,
        CASE
            WHEN dhl.rent < 1500 THEN 'LOW'
            WHEN dhl.rent < 2500 THEN 'MEDIUM'
            ELSE 'HIGH'
        END AS value_segment,
        id_house_listing,
        ROW_NUMBER() OVER (PARTITION BY ldi.id_house, status_history ORDER BY ts_status_started) AS rn
    FROM 
       datalake_rental_historical_follow_up.house_listings_daily_info AS ldi 
    LEFT JOIN 
       dw_rent.dim_house_listing AS dhl 
            ON ldi.id_house_listing = dhl.sk_house_listing
    WHERE  
        status_history = 'PUBLISHED'
        AND ((YEAR = 2023 AND MONTH >= 10) OR (YEAR > 2023))
        AND ts_status_started >= DATE('2023-10-09')
        AND ts_status_started < DATE_TRUNC('MONTH', CURRENT_DATE)
),
db AS (
    SELECT 
        unp.id_house_listing,
        unp.country_code,
        unp.value_segment,
        unp.dt_month_status_started,
        unp.dt_status_started,
        IF(
          pub.dt_status_started > unp.dt_status_started 
          AND DATE_DIFF(pub.dt_status_started, unp.dt_status_started) <= 30
          , 1
          , 0
        ) AS diff_30,
        IF(
          pub.dt_status_started > unp.dt_status_started 
          AND DATE_DIFF(pub.dt_status_started, unp.dt_status_started) <= 90
          , 1
          , 0
        ) AS diff_90
    FROM 
        db_unpublished AS unp 
    LEFT JOIN 
        db_published AS pub 
            ON unp.id_house_listing = pub.id_house_listing
    WHERE 
        unp.rn=1 
        AND ((pub.rn = 1) OR (pub.rn IS NULL))
) 
SELECT  
    CAST(dt_month_status_started AS DATE) AS dt_month_status_started,
    country_code,
    value_segment,
    COUNT(DISTINCT id_house_listing) AS qtd_listings_unp,
    COUNT(DISTINCT 
        IF(
          diff_30 = 1 
          AND dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -30)
          , id_house_listing
          , NULL
        ) 
    ) AS qtd_listings_pub_30d_matured,
    COUNT(DISTINCT 
        IF(
            diff_90 = 1 
            AND dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -90)
            , id_house_listing
            , NULL
          ) 
    ) AS qtd_listings_pub_90d_matured,
    CAST(COUNT(DISTINCT 
        IF(
            diff_30 = 1
            AND dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -30)
            , id_house_listing
            , NULL
          )
        ) AS DOUBLE 
        )  
        / 
        COUNT(DISTINCT 
            IF(
                dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -30)
                , id_house_listing
                , NULL
            )
        ) * 1.0 AS pct_pub_30d_matured,
    CAST(COUNT(DISTINCT 
        IF(
            diff_90 = 1 
            AND dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -90)
            , id_house_listing
            , NULL
          )
        ) AS DOUBLE 
        ) 
        / 
        COUNT(DISTINCT 
            IF(
                dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -90)
                , id_house_listing
                , NULL
            )
        ) * 1.0 AS pct_pub_90d_matured
FROM 
    db 
GROUP BY 
    1, 2, 3

UNION ALL

SELECT  
    CAST(dt_month_status_started AS DATE) AS dt_month_status_started,
    country_code,
    'OVERALL' AS value_segment,
    COUNT(DISTINCT id_house_listing) AS qtd_listings_unp,
    COUNT(DISTINCT 
        IF(
          diff_30 = 1 
          AND dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -30)
          , id_house_listing
          , NULL
        ) 
    ) AS qtd_listings_pub_30d_matured,
    COUNT(DISTINCT 
        IF(
            diff_90 = 1 
            AND dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -90)
            , id_house_listing
            , NULL
          ) 
    ) AS qtd_listings_pub_90d_matured,
    CAST(COUNT(DISTINCT 
        IF(
            diff_30 = 1
            AND dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -30)
            , id_house_listing
            , NULL
          )
        ) AS DOUBLE 
        )  
        / 
        COUNT(DISTINCT 
            IF(
                dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -30)
                , id_house_listing
                , NULL
            )
        ) * 1.0 AS pct_pub_30d_matured,
    CAST(COUNT(DISTINCT 
        IF(
            diff_90 = 1 
            AND dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -90)
            , id_house_listing
            , NULL
          )
        ) AS DOUBLE 
        ) 
        / 
        COUNT(DISTINCT 
            IF(
                dt_month_status_started <= DATE_ADD(DATE_TRUNC('MONTH', CURRENT_DATE), -90)
                , id_house_listing
                , NULL
            )
        ) * 1.0 AS pct_pub_90d_matured
FROM 
    db 
GROUP BY 
    1, 2, 3