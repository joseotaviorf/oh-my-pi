SELECT
    id AS id_pipeline,
    label,
    stages,
    display_order,
    archived AS is_archived,
    archived_at AS ts_archived,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_raw.ticket_pipeline
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}