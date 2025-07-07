SELECT
    id,
    relationships[0].created_by.data.id AS id_user_created_by,
    attributes.title,
    attributes.summary,
    attributes.visibility,
    attributes.degreed_url AS url_degreed,
    CAST(attributes.is_endorsed AS BOOLEAN) AS is_endorsed,
    TO_TIMESTAMP(attributes.created_at) AS ts_created,
    TO_TIMESTAMP(attributes.modified_at) AS ts_modified,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.pathways