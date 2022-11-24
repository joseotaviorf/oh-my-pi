SELECT
    id,
    listingBusinessContext_id AS id_listing_business_context,
    isprimarymarket AS is_primary_market,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.listingsalemodel