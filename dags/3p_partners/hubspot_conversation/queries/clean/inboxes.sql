SELECT
    id AS id_inbox,
    name,
    type,
    CAST(archived AS BOOLEAN) AS is_archived,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    ts_load,
    year,
    month,
    day,
    hour
FROM
    datalake_hubspot_raw.inboxes
WHERE
    ts_load BETWEEN '{load_start_date}' AND '{load_end_date}'