SELECT
    canvas_id AS id_canvas,
    `name` AS canvas_name,
    description AS canvas_description,
    CASE
        WHEN `name` LIKE '%MX%' THEN 'MX'
        WHEN `name` IS NULL THEN 'Undefined'
        ELSE 'BR'
    END AS country_code,
    FROM_JSON(variants, 'array<map<string,string>>') AS variants,
    schedule_type,
    FROM_JSON(steps, 'array<map<string,string>>') AS steps,
    FROM_JSON(channels, 'array<string>') AS channels,
    FROM_JSON(tags, 'array<string>') AS tags,
    REGEXP_EXTRACT(tags, 'journeyStep=(\\w+)') AS journey_step,
    archived,
    draft,
    TO_TIMESTAMP(first_entry) AS ts_first_entry,
    TO_TIMESTAMP(last_entry) AS ts_last_entry,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_braze_details_raw.canvas_details_owners
