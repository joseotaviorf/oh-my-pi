SELECT
    id,
    listingBusinessContext_id AS id_listing_business_context,
    rentalAdministrator AS rental_administrator,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.listingrentmodel