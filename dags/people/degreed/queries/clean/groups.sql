SELECT
    id,
    relationships[0].created_by.data.id AS id_user_created_by,
    attributes.external_group_id AS id_external_group,
    attributes.name,
    attributes.description,
    attributes.privacy,
    CAST(attributes.has_shared_access AS BOOLEAN) AS has_shared_access,
    TO_TIMESTAMP(attributes.created_at) AS ts_created,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.groups