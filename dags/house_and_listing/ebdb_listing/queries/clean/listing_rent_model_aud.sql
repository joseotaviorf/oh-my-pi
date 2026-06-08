SELECT
    id,
    listingBusinessContext_id AS id_listing_business_context,
    rev,
    revtype AS rev_type,
    rentalAdministrator AS rental_administrator,
    rentalAdministrator_MOD AS mod_rental_administrator,
    isEarlyRelisting AS is_early_relisting,
    op_cdc,
    ts_cdc_transaction,
    ts_database_transaction
FROM
    datalake_ebdb_raw.listingrentmodel_aud
