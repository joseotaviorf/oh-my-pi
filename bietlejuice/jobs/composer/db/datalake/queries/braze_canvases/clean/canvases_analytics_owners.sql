SELECT
    canvas_id AS id_canvas,
    `name` AS canvas_name,
    stats
FROM
    datalake_braze_raw.canvases_analytics_owners