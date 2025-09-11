SELECT
    id,
    partner_external_id AS id_partner_external,
    tier_id AS id_tier,
    overwritten_by AS id_overwritten_by,
    partner_external_type,
    incentive_system,
    overwritten_reason,
    TIMESTAMP(validity_start_at) AS ts_validity_start,
    TIMESTAMP(validity_end_at) AS ts_validity_end,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.partner_tier