SELECT
    id,
    attributes.external_id AS id_external,
    attributes.name,
    attributes.description,
    attributes.degreed_url AS url_degreed,
    CAST(attributes.is_endorsed AS BOOLEAN) AS is_endorsed,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.organization_skills
