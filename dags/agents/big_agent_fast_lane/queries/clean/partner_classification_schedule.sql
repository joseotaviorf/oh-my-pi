SELECT
    id,
    partner_classification_id AS id_partner_classification,
    reminder_external_id AS id_reminder_external,
    incentive_system,
    status,
    TIMESTAMP(scheduled_to) AS ts_scheduled_to,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.partner_classification_schedule