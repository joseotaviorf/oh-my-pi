SELECT
    id,
    attributes.skill_unique_identifier AS id_skill,
    attributes.name,
    attributes.description,
    attributes.visibility,
    CAST(attributes.cost AS DECIMAL(10, 2)) AS cost,
    CAST(attributes.is_featured AS BOOLEAN) AS is_featured,
    TO_TIMESTAMP(attributes.created_at) AS ts_created,
    TO_TIMESTAMP(attributes.modified_at) AS ts_modified,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.certifiable_skills