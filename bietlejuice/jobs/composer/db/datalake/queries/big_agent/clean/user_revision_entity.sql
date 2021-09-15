SELECT
    id,
    user_id AS id_user,
    timestamp AS ts_revision,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.user_revision_entity
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
