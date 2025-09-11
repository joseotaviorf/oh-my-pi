SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    external_partner_id AS id_external_partner,
    external_partner_type,
    incentive_system,
    external_partner_id_mod AS mod_id_external_partner,
    external_partner_type_mod AS mod_external_partner_type,
    incentive_system_mod AS mod_incentive_system,
    active_mod AS mod_active,
    CAST(active AS BOOLEAN) AS is_active,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.partner_incentive_system_aud