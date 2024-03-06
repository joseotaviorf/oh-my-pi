SELECT 
    id,
    visitor_id AS id_visitor,
    event_id AS id_event,
    reminder_type_id AS id_reminder_type,
    status,
    created_by,
    closed_by,
    creation_method,
    version,
    date AS ts_reminder,
    created_at AS ts_created,
    updated_at AS ts_updated,
    closed_at AS ts_closed,
    year,
    month,
    day
FROM 
    datalake_hub_services_raw.reminder
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
