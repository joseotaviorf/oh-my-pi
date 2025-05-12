SELECT 
    id,
    name,
    status,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    name_mod AS mod_name,
    status_mod AS mod_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_hub_services_raw.reminder_type_aud