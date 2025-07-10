SELECT
    id,
    zipcode AS zip_code,
    street_name,
    number,
    neighborhood,
    complement,
    city,
    state,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.key_location_return_address
