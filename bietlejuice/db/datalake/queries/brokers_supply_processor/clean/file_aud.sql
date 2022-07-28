SELECT
    id,
    partner_id AS id_partner,
    hash,
    name AS file_name,
    type,
    url,
    file_byte,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    partner_id_mod AS mod_id_partner,
    hash_mod AS mod_hash,
    name_mod AS mod_file_name,
    type_mod AS mod_type,
    url_mod AS mod_url,
    file_byte_mod AS mod_file_byte,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.file_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}