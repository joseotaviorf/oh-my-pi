SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    partner_classification_id AS id_partner_classification,
    reminder_external_id AS id_reminder_external,
    incentive_system,
    status,
    partner_classification_id_mod AS mod_id_partner_classification,
    reminder_external_id_mod AS mod_id_reminder_external,
    incentive_system_mod AS mod_incentive_system,
    status_mod AS mod_status,
    scheduled_to_mod AS mod_scheduled_to,
    TIMESTAMP(scheduled_to) AS ts_scheduled_to,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.partner_classification_schedule_aud