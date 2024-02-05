SELECT
    id,
    correlation_id AS id_correlation,
    user_id AS id_user,
    content_id AS id_content,
    taxonomy,
    taxonomy_submenu,
    journey_name,
    journey_version,
    journey_state,
    status,
    status_error_message,
    origin,
    rule_description,
    submenu_content,
    user_role,
    fired_response,
    shared_var_expiration AS ts_shared_var_expiration,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_journey_flow_raw.t_journey_flow
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
