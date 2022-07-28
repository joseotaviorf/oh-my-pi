SELECT
    id,
    company_uuid AS uuid_company,
    public_area,
    country,
    state,
    city,
    neighborhood,
    zip_code,
    number,
    complement,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    company_uuid_mod AS mod_uuid_company,
    zip_code_mod AS mod_zip_code,
    public_area_mod AS mod_public_area,
    number_mod AS mod_number,
    complement_mod AS mod_complement,
    neighborhood_mod AS mod_neighborhood,
    city_mod AS mod_city,
    country_mod AS mod_country,
    state_mod AS mod_state,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.address_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}