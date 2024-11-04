SELECT
    id_house,
    id_house_listing,
    listing_age,
    quality_score,
    liquidity_score,
    qt_lpv_1d_for_rent,
    qt_lpv_3d_for_rent,
    qt_lpv_7d_for_rent,
    qt_lpv_1d_for_sale,
    qt_lpv_3d_for_sale,
    qt_lpv_7d_for_sale,
    demand_score,
    dt_publication_for_sale,
    dt_publication_for_rent,
    dt_snapshot
FROM
    reverse_demand_score.listing_demand_score
WHERE
    DATE(dt_snapshot) = CURRENT_DATE()
    -- TO-DO: Add filter for campaigns (collecting with BizOps team)