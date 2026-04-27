SELECT
    id,
    managed_rental_uuid,
    contract_uuid,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.managed_rental
