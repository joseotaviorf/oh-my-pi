SELECT
    id,
    app_label,
    model AS content_model,
    NOW() AS ts_load
FROM
    datalake_legaut_raw.django_content_type
