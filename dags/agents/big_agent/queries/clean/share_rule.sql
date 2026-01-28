SELECT
    id,
    external_condition_id AS id_external_condition,
    external_condition_type,
    program_code,
    name,
    value,
    extra_value,
    min_score,
    max_score,
    status,
    DATE(start_at) AS dt_started,
    DATE(end_at) AS dt_ended,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.share_rule