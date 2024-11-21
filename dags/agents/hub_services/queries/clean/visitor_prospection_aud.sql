SELECT 
    id,
    visitor_id AS id_visitor,
    responsible_id AS id_responsible,
    reminder_id AS id_reminder,
    reminder_type_id AS id_reminder_type,
    priority_lead_status,
    priority_lead_type,
    reminder_type_name,
    reminder_status,
    reminder_creation_method,
    reminder_event_type,
    sorting_order,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    visitor_id_mod AS mod_visitor_id,
    responsible_id_mod AS mod_responsible_id,
    reminder_id_mod AS mod_reminder_id,
    reminder_type_id_mod AS mod_reminder_type_id,
    priority_lead_status_mod AS mod_priority_lead_status,
    priority_lead_type_mod AS mod_priority_lead_type,
    reminder_type_name_mod AS mod_reminder_type_name,
    reminder_status_mod AS mod_reminder_status,
    reminder_creation_method_mod AS mod_reminder_creation_method,
    reminder_event_type_mod AS mod_reminder_event_type,
    sorting_order_mod AS mod_sorting_order,
    reminder_date_mod AS mod_reminder_date,
    reminder_date AS ts_reminder,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_hub_services_raw.visitor_prospection_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}