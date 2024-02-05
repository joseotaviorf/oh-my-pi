SELECT
    id,
    journey_id AS id_journey,
    correlation_id AS id_correlation,
    user_id AS id_user,
    content_id AS id_content,
    message_from,
    message_to,
    message_content,
    step_status,
    step_message,
    journey_name,
    journey_version,
    journey_step_name,
    journey_step_type,
    elapsed_time,
    creation AS ts_created,
    year,
    month,
    day
FROM
    datalake_journey_flow_raw.t_dialog
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
