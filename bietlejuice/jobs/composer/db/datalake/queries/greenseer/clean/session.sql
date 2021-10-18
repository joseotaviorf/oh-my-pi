SELECT
    session_id AS id_session,
    pipeline_id AS id_pipeline,
    language_code,
    CAST(memory AS VARCHAR(60000)) AS memory,
    current_state,
    beginning_timestamp AS ts_started,
    end_timestamp AS ts_ended
FROM
    datalake_greenseer_raw.session
