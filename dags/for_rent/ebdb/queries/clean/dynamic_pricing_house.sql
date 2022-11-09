select
  id,
  houseId as id_house,
  minRent as min_rent,
  initialRent as initial_rent,
  lastPriceUpdate as dt_last_price_updated,
  dynamicPricingParameterId as id_dynamic_pricing_parameter,
  criadoEm as ts_created,
  atualizadoEm as ts_updated,
  status,
  priceChangesOccurred as occurred_price_changes,
  enabled as is_enabled,
  operationmode as operation_mode,
  origin,
  prepublicationrentprobability as pre_publication_rent_probability
from datalake_ebdb_raw.dynamicpricinghouse
