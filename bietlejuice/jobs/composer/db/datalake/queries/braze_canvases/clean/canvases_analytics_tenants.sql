SELECT
    canvas_id AS id_canvas,
    messages,
    conversions_by_send_time,
    conversions1_by_send_time,
    conversions2_by_send_time,
    conversions3_by_send_time,
    conversions,
    conversions1,
    conversions2,
    conversions3,
    unique_recipients,
    revenue,
    TO_TIMESTAMP(`time`) AS ts_canvas_analytics_time
FROM
    datalake_braze_raw.canvases_analytics_tenants