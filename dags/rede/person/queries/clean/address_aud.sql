SELECT
    id,
    person_id AS id_person,
    country,
    state,
    city,
    neighborhood,
    address,
    zip_code,
    complement,
    number,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    person_id_mod AS mod_id_person,
    country_mod AS mod_country,
    state_mod AS mod_state,
    city_mod AS mod_city,
    neighborhood_mod AS mod_neighborhood,
    address_mod AS mod_address,
    zip_code_mod AS mod_zip_code,
    complement_mod AS mod_complement,
    number_mod AS mod_number,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.address_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}