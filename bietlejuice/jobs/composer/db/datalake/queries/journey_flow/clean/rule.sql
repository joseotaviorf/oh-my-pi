SELECT
    application_name,
    application_event,
    version,
    status,
    content,
    created_by_user,
    approved_by_user,
    created_at AS ts_created,
    updated_at AS ts_updated,
    approved_at AS ts_approved
FROM 
    datalake_journey_flow_raw.t_rule 