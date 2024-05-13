SELECT
  id,
  houseId AS id_house,
  listingBusinessContextId AS id_listing_business_context,
  dynamicPricingParameterId AS id_dynamic_pricing_parameter,
  status,
  operationmode AS operation_mode,
  origin,
  minRent AS min_rent,
  initialRent AS initial_rent,
  priceChangesOccurred AS occurred_price_changes,
  prepublicationrentprobability AS pre_publication_rent_probability,
  enabled AS is_enabled,
  lastPriceUpdate AS dt_last_price_updated,
  activatedAt AS dt_activated,
  deactivatedAt AS dt_deactivated,
  atualizadoEm AS ts_updated,
  criadoEm AS ts_created
FROM 
  datalake_ebdb_raw.dynamicpricinghouse
