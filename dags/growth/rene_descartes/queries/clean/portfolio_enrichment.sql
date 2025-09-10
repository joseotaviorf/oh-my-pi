SELECT
    portfolio_id AS id_portfolio,
    dejavu_id AS id_dejavu,
    dejavu_reliability,
    dejavu_version,
    price_listing_rent,
    price_listing_sale,
    property_prediction_price_rent,
    property_prediction_response_rent,
    property_prediction_origin_rent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) as day
FROM
    datalake_rene_descartes_raw.portfolio_enrichment
