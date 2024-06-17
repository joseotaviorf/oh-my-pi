WITH house_metrics AS (
  SELECT
    id_house,
    business_context,
    MEDIAN(CASE WHEN similar_house_status = 'on-market' THEN similar_price END) AS on_market_price_median,
    MEDIAN(CASE WHEN similar_house_status = 'off-market' THEN similar_price END) AS off_market_price_median,
    MEDIAN(CASE WHEN similar_house_status = 'on-market' THEN similar_rent_total_value END) AS on_market_total_value_median,
    MEDIAN(CASE WHEN similar_house_status = 'off-market' THEN similar_rent_total_value END) AS off_market_total_value_median,
    MEDIAN(CASE WHEN similar_house_status = 'on-market' THEN similar_sale_price_m2 END) AS on_market_price_by_square_meter,
    MEDIAN(CASE WHEN similar_house_status = 'off-market' THEN similar_sale_price_m2 END) AS off_market_price_by_square_meter,
    MEDIAN(CASE WHEN similar_house_status = 'on-market' THEN similar_days_in_the_market END) AS on_market_days_in_the_market,
    MEDIAN(CASE WHEN similar_house_status = 'off-market' THEN similar_days_in_the_market END) AS off_market_days_to_contract_sign
  FROM
    datalake_atlas_pricing_report.similar_listings
  GROUP BY ALL
),
condo_metrics AS (
  SELECT
    id_house,
    MEDIAN(similar_condo) AS condominium_price_median,
    MEDIAN(similar_iptu) AS urban_property_tax_median
  FROM
    datalake_atlas_pricing_report.house_condo_metrics
  GROUP BY ALL
)
SELECT
  DATE_FORMAT(NOW(), 'yyyy-MM-dd\'T\'HH:mm:ss') AS ts_event,
  MONOTONICALLY_INCREASING_ID() AS id,
  house_metrics.id_house::BIGINT,
  house_metrics.business_context::STRING,
  hlvm.views_quantity::BIGINT,
  COALESCE(hlvm.demand_level, 'NO_VIEWS')::STRING AS demand_level,
  condo_metrics.condominium_price_median::BIGINT,
  condo_metrics.urban_property_tax_median::BIGINT,
  house_metrics.on_market_price_median::BIGINT,
  house_metrics.on_market_price_by_square_meter::BIGINT,
  house_metrics.off_market_price_median::BIGINT,
  house_metrics.off_market_price_by_square_meter::BIGINT,
  house_metrics.on_market_total_value_median::BIGINT,
  house_metrics.off_market_total_value_median::BIGINT,
  house_metrics.on_market_days_in_the_market::BIGINT,
  house_metrics.off_market_days_to_contract_sign::BIGINT
FROM
  house_metrics
LEFT JOIN
  condo_metrics
    ON house_metrics.id_house = condo_metrics.id_house
LEFT JOIN
  datalake_atlas_pricing_report.house_listing_views_metrics AS hlvm
    ON house_metrics.id_house = hlvm.id_house
      AND house_metrics.business_context = hlvm.business_context
