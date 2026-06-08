SELECT
    id,
    listingBusinessContext_id AS id_listing_business_context,
    isprimarymarket AS is_primary_market,
    hasGreatSalePriceTag AS has_great_sale_price_tag,
    created_at AS ts_created,
    updated_at AS ts_updated,
    op_cdc,
    ts_cdc_transaction,
    ts_database_transaction
FROM
    datalake_ebdb_raw.listingsalemodel
