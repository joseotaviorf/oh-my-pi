SELECT
    id,
    external_condition_id AS id_external_condition,
    external_condition_type,
    program_code,
    operation,
    status,
    trigger,
    points,
    max_points,
    DATE(start_at) AS dt_start,
    DATE(end_at) AS dt_end,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.points_rule
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}