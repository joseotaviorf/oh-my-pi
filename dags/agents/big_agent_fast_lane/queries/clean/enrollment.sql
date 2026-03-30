SELECT
    id,
    agent_id AS id_agent,
    program_id AS id_program,
    details,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.enrollment