SELECT 
    id,
    correlation_id AS id_correlation,
    user_id AS id_user,
    content_id AS id_content,
    taxonomy,
    journey_name,
    journey_version,
    status,
    status_error_message,
    journey_state,
    shared_var_expiration,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_journey_flow_raw.t_journey_flow 