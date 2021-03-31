SELECT
    id,
    ccv_id AS id_ccv,
    address_data_id AS id_address_data,
    type,
    name,
    email,
    document,
    nationality,
    profession,
    marital_status,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    ccv_id_mod AS mod_id_ccv,
    address_data_id_mod AS mod_id_address_data,
    type_mod AS mod_type,
    name_mod AS mod_name,
    email_mod AS mod_email,
    document_mod AS mod_document,
    nationality_mod AS mod_nationality,
    profession_mod AS mod_profession,
    marital_status_mod AS mod_marital_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_party_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}