SELECT
    id,
    listingBusinessContext_id AS id_listing_business_context,
    isprimarymarket AS is_primary_market,
    hasGreatSalePriceTag AS has_great_sale_price_tag,
    saleType AS sale_type,
    unitCount AS unit_count,
    minPrice AS min_price,
    maxPrice AS max_price,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.listingsalemodel
