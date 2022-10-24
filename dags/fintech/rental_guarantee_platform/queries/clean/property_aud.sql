SELECT
    id,
    address_id AS id_address,
    type,
    identification,
    business_line,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    address_id_mod AS mod_id_address,
    type_mod AS mod_type,
    identification_mod AS mod_identification,
    business_line_mod AS mod_business_line,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.property_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}