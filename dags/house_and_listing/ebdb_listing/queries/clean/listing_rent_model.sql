SELECT
    id,
    listingBusinessContext_id AS id_listing_business_context,
    rentalAdministrator AS rental_administrator,
    isEarlyRelisting AS is_early_relisting,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.listingrentmodel
