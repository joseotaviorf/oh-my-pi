SELECT
    id,
    zip_code,
    street,
    complement,
    neighborhood,
    city,
    state,
    country,
    address_type,
    version,
    number,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    zip_code_mod AS mod_zip_code,
    street_mod AS mod_street,
    number_mod AS mod_number,
    complement_mod AS mod_complement,
    neighborhood_mod AS mod_neighborhood,
    city_mod AS mod_city,
    state_mod AS mod_state,
    country_mod AS mod_country,
    address_type_mod AS mod_address_type,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.address_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
