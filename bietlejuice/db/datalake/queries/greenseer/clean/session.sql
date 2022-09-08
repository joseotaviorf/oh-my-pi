SELECT
    session_id AS id_session,
    pipeline_id AS id_pipeline,
    language_code,
    memory,
    current_state,
    beginning_timestamp AS ts_started,
    end_timestamp AS ts_ended,
    year,
    month,
    day
FROM
    datalake_greenseer_raw.session
WHERE
    DATE(CONCAT(year,'-',month,'-',day)) >= DATE('{year}-{month}-{day}') - INTERVAL 4 days
