SELECT
    session_id AS id_session,
    pipeline_id AS id_pipeline,
    language_code,
    memory,
    current_state,
    beginning_timestamp AS ts_started,
    end_timestamp AS ts_ended,
    update_timestamp AS ts_updated,
    year,
    month,
    day
FROM
    datalake_greenseer_raw.session
