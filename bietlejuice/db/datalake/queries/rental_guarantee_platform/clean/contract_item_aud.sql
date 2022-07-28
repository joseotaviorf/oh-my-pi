SELECT
    id,
    contract_id AS id_contract,
    description,
    value,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    contract_id_mod AS mod_id_contract,
    description_mod AS mod_description,
    value_mod AS mod_value,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract_item_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}