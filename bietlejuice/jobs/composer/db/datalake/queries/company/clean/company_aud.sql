SELECT
    id,
    company_uuid AS uuid_company,
    parent_id AS id_parent,
    company_name,
    trade_name,
    company_type,
    status,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    parent_id_mod AS mod_id_parent,
    company_uuid_mod AS mod_uuid_company,
    company_name_mod AS mod_company_name,
    trade_name_mod AS mod_trade_name,
    company_type_mod AS mod_company_type,
    status_mod AS mod_status,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_company_raw.company_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}