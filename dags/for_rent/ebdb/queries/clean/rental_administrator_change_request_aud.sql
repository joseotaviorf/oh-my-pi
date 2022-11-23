SELECT
    id AS id_rental_administrator_change_request,
    houseId AS id_house,
    rev,
    revtype AS rev_type,
    oldRentalAdministrator AS old_rental_administrator,
    newRentalAdministrator AS new_rental_administrator,
    status,
    status_MOD AS mod_status,
    migratedAt_MOD AS mod_migrated,
    created_at AS ts_created,
    migratedAt AS ts_migrated
FROM
    datalake_ebdb_raw.rentaladministratorchangerequest_aud