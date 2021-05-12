SELECT
    canvas_id AS id_canvas,
    `name` AS canvas_name,
    description AS canvas_description,
    variants,
    schedule_type,
    steps,
    channels,
    tags,
    archived,
    draft,
    TO_TIMESTAMP(first_entry) AS ts_first_entry,
    TO_TIMESTAMP(last_entry) AS ts_last_entry,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_braze_raw.canvas_details_owners