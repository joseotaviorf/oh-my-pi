SELECT
    id,
    partner_external_id AS id_partner_external,
    partner_external_type,
    status,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.partner_classification