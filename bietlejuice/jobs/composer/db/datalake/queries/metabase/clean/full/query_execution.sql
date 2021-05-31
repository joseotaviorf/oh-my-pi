SELECT
    id,
    executor_id AS id_user_executor,
    card_id AS id_card,
    dashboard_id AS id_dashboard,
    pulse_id AS id_pulse,
    database_id AS id_database,
    hash,
    context,
    result_rows,
    error AS error_message,
    running_time AS running_time_in_milliseconds,
    native AS is_native,
    started_at AS ts_started
FROM
    datalake_metabase_raw.query_execution