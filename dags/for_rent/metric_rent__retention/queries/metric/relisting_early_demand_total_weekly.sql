
SELECT 
    CAST(DATE_TRUNC('WEEK', ts_publication) AS DATE) AS dt_week_publication,
    COUNT(DISTINCT 
      IF(
        listing_category_start = 'Re-Listing' 
        AND is_early_demand IS TRUE
        , sk_house_listing
        , NULL
      )
    ) AS qtd_ed_rl, 
    COUNT(DISTINCT 
      IF(
        listing_category_start = 'Re-Listing'
        , sk_house_listing
        , NULL
      )
    ) AS qtd_rl,
    CAST(
      COUNT(DISTINCT 
        IF(
          listing_category_start = 'Re-Listing' 
          AND is_early_demand IS TRUE
          , sk_house_listing
          , NULL
        )
      ) AS DOUBLE
    ) 
    / 
    COUNT(DISTINCT 
      IF(
        listing_category_start = 'Re-Listing'
        , sk_house_listing
        , NULL
      )
    ) * 1.0 AS pct_ed_rl
FROM 
    dw_rent.dim_house_listing
GROUP BY 
    1