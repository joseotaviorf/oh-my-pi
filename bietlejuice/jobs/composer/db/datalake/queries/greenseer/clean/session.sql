SELECT
    session_id AS id_session,
    pipeline_id AS id_pipeline,
    language_code,
    memory,
    metadata,
    current_state,
    beginning_timestamp AS ts_started,
    end_timestamp AS ts_ended
FROM
    datalake_greenseer_raw.session
