SELECT
    id,
    attributes.external_id AS id_external,
    attributes.name,
    attributes.subtitle,
    attributes.description,
    attributes.plan_type,
    attributes.visibility,
    attributes.image_url AS url_image,
    attributes.degreed_url AS url_degreed,
    CAST(attributes.can_collaborate AS BOOLEAN) AS is_collaborative,
    CAST(attributes.can_follow AS BOOLEAN) AS is_followable,
    CAST(attributes.is_endorsed AS BOOLEAN) AS is_endorsed,
    TO_TIMESTAMP(attributes.created_at) AS ts_created,
    TO_TIMESTAMP(attributes.modified_at) AS ts_modified,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.skill_plans