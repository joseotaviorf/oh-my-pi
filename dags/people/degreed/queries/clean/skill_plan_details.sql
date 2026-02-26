SELECT
    id,
    attributes.external_id AS id_external,
    relationships,
    attributes.name,
    attributes.subtitle,
    NULLIF(attributes.description, '') AS description,
    type,
    attributes.plan_type,
    attributes.visibility,
    attributes.degreed_url AS url_degreed,
    attributes.image_url AS url_image,
    CAST(attributes.can_collaborate AS BOOLEAN) AS is_collaborative,
    CAST(attributes.can_follow AS BOOLEAN) AS is_followable,
    CAST(attributes.is_endorsed AS BOOLEAN) AS is_endorsed,
    attributes.collaborators,
    attributes.sections,
    included,
    links,
    TO_TIMESTAMP(attributes.created_at) AS ts_created,
    TO_TIMESTAMP(attributes.modified_at) AS ts_modified,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.skill_plan_details
