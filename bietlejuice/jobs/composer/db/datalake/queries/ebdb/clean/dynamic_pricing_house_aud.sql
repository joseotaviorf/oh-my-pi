select
    REV as rev,
    REVTYPE as rev_type,
    id,
    houseId as id_house,
    minRent as min_rent,
    initialRent as initial_rent,
    lastPriceUpdate as last_price_updated,
    dynamicPricingParameterId as id_dynamic_pricing_parameter,
    active as is_active,
    status,
    status_MOD as mod_status,
    dynamicPricingParameterId_MOD as mod_id_dynamic_pricing_parameter,
    priceChangesOccurred as price_changes_occurred,
    priceChangesOccurred_MOD as mod_price_changes_occurred
from
    datalake_ebdb_raw.dynamicpricinghouse_aud
