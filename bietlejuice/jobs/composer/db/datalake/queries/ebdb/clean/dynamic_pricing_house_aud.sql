select
    REV as rev,
    REVTYPE as rev_type,
    id,
    houseId as id_house,
    minRent as min_rent,
    initialRent as initial_rent,
    lastPriceUpdate as last_price_updated,
    dynamicPricingParameterId as id_dynamic_pricing_parameter,
    status,
    status_MOD as mod_status,
    dynamicPricingParameterId_MOD as mod_id_dynamic_pricing_parameter,
    priceChangesOccurred as price_changes_occurred,
    priceChangesOccurred_MOD as mod_price_changes_occurred,
    enabled as is_enabled,
    enabled_MOD as mod_is_enabled,
    operationmode as operation_mode,
    operationmode_mod as mod_operation_mode,
    origin,
    origin_mod as mod_origin,
    prepublicationrentprobability as pre_publication_rent_probability,
    prepublicationrentprobability_mod as mod_pre_publication_rent_probability
from
    datalake_ebdb_raw.dynamicpricinghouse_aud
