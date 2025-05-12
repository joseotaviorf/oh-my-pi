SELECT
    id,
    external_id AS id_external,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    version,
    name AS visitor_name,
    email,
    phone_number,
    id_mod AS mod_id,
    name_mod AS mod_visitor_name,
    email_mod AS mod_email,
    phone_number_mod AS mod_phone_number,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.visitor_aud