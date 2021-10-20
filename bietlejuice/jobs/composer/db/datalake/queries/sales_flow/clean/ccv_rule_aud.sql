SELECT 
    id AS id_ccv_rule_aud,
    ccv_version,
    type,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    name AS ccv_rule_name,
    storage_hash_token,
    checksum,
    ccv_version_mod AS mod_ccv_version,
    type_mod AS mod_type,
    name_mod AS mod_ccv_rule_name,
    storage_hash_token_mod AS mod_storage_hash_token, 
    checksum_mod AS mod_checksum,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_rule_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}