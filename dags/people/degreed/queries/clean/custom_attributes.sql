SELECT
    id,
    attributes.name,
    attributes.data_type AS data_type,
    CAST(attributes.is_visible_in_ui AS BOOLEAN) AS is_visible_in_ui,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.custom_attributes
