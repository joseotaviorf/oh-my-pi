SELECT
    id,
    attributes.name,
    attributes.url,
    attributes.provider_content_visibility AS provider_content_visibility,
    CAST(attributes.is_active AS BOOLEAN) AS is_active,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.providers
