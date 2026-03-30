WITH brokers_regions AS (
  SELECT
    cbp.sk_broker_product,
    EXPLODE(SPLIT(cbp.region_list, ',')) AS sk_region
  FROM
    core_brokers.brokers_product AS cbp
)
SELECT
  CONCAT_WS(0, cbp.sk_broker_product, br.sk_region) AS sk_broker_region,
  cbp.sk_broker,
  br.sk_region,
  cbp.product_name,
  cbp.business_context,
  cr.region_name,
  cr.city_region_name,
  cr.level,
  cr.greater_region,
  cr.state_name,
  cr.state_abbreviation,
  cr.country_name,
  cr.country_default_timezone,
  TRUE AS has_3p_access_control,
  CURRENT_TIMESTAMP() AS ts_load
FROM
  brokers_regions AS br
LEFT JOIN
  core_brokers.brokers_product AS cbp
    ON br.sk_broker_product = cbp.sk_broker_product
LEFT JOIN
  core_region.region AS cr
    ON br.sk_region = cr.id_region