WITH 
db_unpublished AS (
    SELECT 
        DATE_TRUNC('WEEK', ts_status_started) AS dt_week_status_started,
        DATE(ts_status_started) AS dt_status_started,
        ldi.country_code,
        CASE
            WHEN dhl.rent < 1500 THEN 'LOW'
            WHEN dhl.rent < 2500 THEN 'MEDIUM'
            ELSE 'HIGH'
        END AS value_segment,
        id_house_listing,
        ROW_NUMBER() OVER (PARTITION BY id_house_listing ORDER BY ts_status_started ) AS rn
    FROM 
        datalake_rental_historical_follow_up.house_listings_daily_info AS ldi
    INNER JOIN
       dw_rent.dim_house_listing AS dhl 
            ON ldi.id_house_listing = dhl.sk_house_listing    
    WHERE  
        status_history = 'UNPUBLISHED'
        AND YEAR >= 2022
        AND ts_status_started >= DATE('2022-09-01')
        AND ts_status_started < DATE_TRUNC('WEEK', CURRENT_DATE) 
        AND dhl.listing_category_start = 'Re-Listing'
),
db_published AS (
    SELECT 
        DATE_TRUNC('WEEK', ts_status_started) AS dt_week_status_started,
        DATE(ts_status_started) AS dt_status_started,
        ldi.country_code,
        CASE
            WHEN dhl.rent < 1500 THEN 'LOW'
            WHEN dhl.rent < 2500 THEN 'MEDIUM'
            ELSE 'HIGH'
        END AS value_segment,
        id_house_listing
    FROM 
       datalake_rental_historical_follow_up.house_listings_daily_info AS ldi 
    INNER JOIN
       dw_rent.dim_house_listing AS dhl 
            ON ldi.id_house_listing = dhl.sk_house_listing
    WHERE  
        status_history = 'PUBLISHED'
        AND YEAR >= 2022
        AND ts_status_started >= DATE('2022-09-01')
        AND ts_status_started < DATE_TRUNC('WEEK', CURRENT_DATE)
),
db_prep AS (
    SELECT 
        unp.id_house_listing,
        unp.country_code,
        unp.value_segment,
        unp.dt_week_status_started,
        unp.dt_status_started AS dt_unp,
        pub.dt_status_started AS dt_pub,
        CASE WHEN pub.dt_status_started IS NULL THEN 1 ELSE ROW_NUMBER() OVER (PARTITION BY pub.id_house_listing ORDER BY pub.dt_status_started) END AS rn
    FROM 
        db_unpublished unp 
    LEFT JOIN 
        db_published pub 
            ON unp.id_house_listing = pub.id_house_listing
                AND unp.dt_status_started <= pub.dt_status_started
    WHERE 
        unp.rn = 1 -- first unpublished
),
db AS (
    SELECT 
        id_house_listing,
        country_code,
        value_segment,
        dt_week_status_started,
        dt_unp AS dt_status_started,
        IF(
          dt_pub > dt_unp
          AND DATE_DIFF(dt_pub, dt_unp) <= 7
          , 1
          , 0
        ) AS diff_7,
        IF(
          dt_pub > dt_unp
          AND DATE_DIFF(dt_pub, dt_unp) <= 30
          , 1
          , 0
        ) AS diff_30,
        IF(
          dt_pub > dt_unp
          AND DATE_DIFF(dt_pub, dt_unp) <= 90
          , 1
          , 0
        ) AS diff_90
    FROM 
        db_prep
    WHERE 
        rn=1
)
SELECT  
    CAST(dt_week_status_started AS DATE) AS dt_week_status_started,
    country_code,
    value_segment,
    COUNT(DISTINCT id_house_listing) AS qtd_listings_unp,
    COUNT(DISTINCT 
        IF(
          diff_7 = 1 
          AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -7)
          , id_house_listing
          , NULL
        ) 
    ) AS qtd_listings_pub_7d_matured,
    COUNT(DISTINCT 
        IF(
          diff_30 = 1 
          AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -30)
          , id_house_listing
          , NULL
        ) 
    ) AS qtd_listings_pub_30d_matured,
    COUNT(DISTINCT 
        IF(
            diff_90 = 1 
            AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -90)
            , id_house_listing
            , NULL
          ) 
    ) AS qtd_listings_pub_90d_matured,
    CAST(COUNT(DISTINCT 
        IF(
            diff_7 = 1
            AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -7)
            , id_house_listing
            , NULL
          )
        ) AS DOUBLE 
        )  
        / 
        COUNT(DISTINCT 
            IF(
                dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -7)
                , id_house_listing
                , NULL
            )
        ) * 1.0 AS pct_pub_7d_matured,
    CAST(COUNT(DISTINCT 
        IF(
            diff_30 = 1
            AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -30)
            , id_house_listing
            , NULL
          )
        ) AS DOUBLE 
        )  
        / 
        COUNT(DISTINCT 
            IF(
                dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -30)
                , id_house_listing
                , NULL
            )
        ) * 1.0 AS pct_pub_30d_matured,
    CAST(COUNT(DISTINCT 
        IF(
            diff_90 = 1 
            AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -90)
            , id_house_listing
            , NULL
          )
        ) AS DOUBLE 
        ) 
        / 
        COUNT(DISTINCT 
            IF(
                dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -90)
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
    CAST(dt_week_status_started AS DATE) AS dt_week_status_started,
    country_code,
    'OVERALL' AS value_segment,
    COUNT(DISTINCT id_house_listing) AS qtd_listings_unp,
    COUNT(DISTINCT 
        IF(
          diff_7 = 1 
          AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -7)
          , id_house_listing
          , NULL
        ) 
    ) AS qtd_listings_pub_7d_matured,
    COUNT(DISTINCT 
        IF(
          diff_30 = 1 
          AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -30)
          , id_house_listing
          , NULL
        ) 
    ) AS qtd_listings_pub_30d_matured,
    COUNT(DISTINCT 
        IF(
            diff_90 = 1 
            AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -90)
            , id_house_listing
            , NULL
          ) 
    ) AS qtd_listings_pub_90d_matured,
    CAST(COUNT(DISTINCT 
        IF(
            diff_7 = 1
            AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -7)
            , id_house_listing
            , NULL
          )
        ) AS DOUBLE 
        )  
        / 
        COUNT(DISTINCT 
            IF(
                dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -7)
                , id_house_listing
                , NULL
            )
        ) * 1.0 AS pct_pub_7d_matured,
    CAST(COUNT(DISTINCT 
        IF(
            diff_30 = 1
            AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -30)
            , id_house_listing
            , NULL
          )
        ) AS DOUBLE 
        )  
        / 
        COUNT(DISTINCT 
            IF(
                dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -30)
                , id_house_listing
                , NULL
            )
        ) * 1.0 AS pct_pub_30d_matured,
    CAST(COUNT(DISTINCT 
        IF(
            diff_90 = 1 
            AND dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -90)
            , id_house_listing
            , NULL
          )
        ) AS DOUBLE 
        ) 
        / 
        COUNT(DISTINCT 
            IF(
                dt_week_status_started <= DATE_ADD(DATE_TRUNC('WEEK', CURRENT_DATE), -90)
                , id_house_listing
                , NULL
            )
        ) * 1.0 AS pct_pub_90d_matured
FROM 
    db 
GROUP BY 
    1, 2, 3