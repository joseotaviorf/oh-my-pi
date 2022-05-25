SELECT
    session_id AS id_session,
    pipeline_id AS id_pipeline,
    language_code,
    memory,
    current_state,
    DATE(DATE_TRUNC('month', beginning_timestamp)) AS dt_month_started,
    beginning_timestamp AS ts_started,
    end_timestamp AS ts_ended
FROM
    datalake_greenseer_raw.session
