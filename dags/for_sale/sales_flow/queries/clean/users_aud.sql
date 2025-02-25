SELECT
    id,
    external_id AS id_external,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    name,
    email,
    phone,
    type,
    cpf,
    external_id_mod AS mod_id_external,
    name_mod AS mod_name,
    email_mod AS mod_email,
    phone_mod AS mod_phone,
    type_mod AS mod_type,
    cpf_mod AS mod_cpf,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.users_aud
