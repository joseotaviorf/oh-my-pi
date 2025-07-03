SELECT
    p.id,
    p.attributes.name,
    p.attributes.url,
    p.attributes.provider_content_visibility AS provider_content_visibility,
    CAST(p.attributes.is_active AS BOOLEAN) AS is_active,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.providers AS p
