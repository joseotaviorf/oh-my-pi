SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    partner_external_id AS id_partner_external,
    partner_external_type,
    status,
    partner_external_id_mod AS mod_id_partner_external,
    partner_external_type_mod AS mod_partner_external_type,
    status_mod AS mod_status,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.partner_classification_aud