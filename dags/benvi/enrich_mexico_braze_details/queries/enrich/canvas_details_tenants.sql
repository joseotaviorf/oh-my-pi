SELECT
    id_canvas,
    canvas_name,
    canvas_description,
    variants,
    schedule_type,
    steps,
    channels,
    tags,
    archived AS is_archived,
    draft AS is_draft,
    ts_first_entry,
    ts_last_entry,
    ts_created,
    ts_updated,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    datalake_braze_details_clean.canvas_details_tenants
WHERE
    DATE(ts_updated) = DATE('{year}-{month}-{day}')
    AND canvas_name LIKE '%MX%'