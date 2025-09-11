SELECT
    id,
    external_partner_id AS id_external_partner,
    external_partner_type,
    incentive_system,
    CAST(active AS BOOLEAN) AS is_active,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.partner_incentive_system