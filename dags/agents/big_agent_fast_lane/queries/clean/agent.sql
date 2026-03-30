SELECT
    id,
    metadata AS details,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.agent