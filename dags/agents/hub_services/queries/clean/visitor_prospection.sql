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
    reminder_date AS ts_reminder,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_hub_services_raw.visitor_prospection
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
