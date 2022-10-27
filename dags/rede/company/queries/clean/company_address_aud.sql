SELECT
    address_id AS id_address,
    company_id AS id_company,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    address_id_mod AS mod_id_address,
    subsidiary_id_mod AS mod_id_subsidiary,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.company_address_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}