SELECT
    id,
    prospectId AS id_prospect,
    agentId AS id_agent,
    agent,
    status,
    via,
    output,
    proactive AS is_proactive,
    createdAt AS ts_created,
    dueAt AS ts_due,
    startedAt AS ts_started,
    finishedAt AS ts_finished,
    year,
    month,
    day
FROM
    datalake_sirena_raw.interactions
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}