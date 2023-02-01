SELECT
    id,
    listingBusinessContext_id AS id_listing_business_context,
    rev,
    revtype AS rev_type,
    isPrimaryMarket AS is_primary_market,
    isPrimaryMarket_MOD AS mod_is_primary_market,
    hasGreatSalePriceTag AS has_great_sale_price_tag,
    hasGreatSalePriceTag_MOD AS mod_has_great_sale_price_tag
FROM
    datalake_ebdb_raw.listingsalemodel_aud