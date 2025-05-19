SELECT
    id AS id_task,
    properties,
    properties_with_history,
    associations,
    archived AS is_archived,
    archived_at AS ts_archived,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_raw.task
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}