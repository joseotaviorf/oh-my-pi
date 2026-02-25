SELECT
    id,
    type AS resource_type,
    element_at(relationships, 2).created_by.data.id AS id_user_created_by,
    attributes.title,
    NULLIF(attributes.summary, '') AS summary,
    attributes.visibility,
    attributes.degreed_url AS url_degreed,
    CAST(attributes.is_endorsed AS BOOLEAN) AS is_endorsed,
    CAST(attributes.share_author_permission AS BOOLEAN) AS is_share_author_permission,
    CAST(attributes.duration_display_disabled AS BOOLEAN) AS is_duration_display_disabled,
    CAST(attributes.header_image_disabled AS BOOLEAN) AS is_header_image_disabled,
    attributes.image_url AS url_image,
    attributes.sections,
    TO_TIMESTAMP(attributes.created_at) AS ts_created,
    TO_TIMESTAMP(attributes.modified_at) AS ts_modified,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.pathway_details
