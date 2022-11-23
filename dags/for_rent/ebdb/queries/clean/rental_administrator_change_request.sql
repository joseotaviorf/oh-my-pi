SELECT
    id AS id_rental_administrator_change_request,
    houseId AS id_house,
    oldRentalAdministrator AS old_rental_administrator,
    newRentalAdministrator AS new_rental_administrator,
    status,
    migratedAt AS ts_migrated,
    updated_at AS ts_updated,
    created_at AS ts_created
FROM
    datalake_ebdb_raw.rentaladministratorchangerequest