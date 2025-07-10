SELECT
    id,
    name,
    phone,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.key_holder_preference
