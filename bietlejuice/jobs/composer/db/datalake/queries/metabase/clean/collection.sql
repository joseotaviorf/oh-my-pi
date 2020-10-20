SELECT
    id,
    personal_owner_id AS id_user_personal_owner,
    name,
    description,
    location,
    slug,
    archived AS is_archived
FROM 
    datalake_metabase_raw.collection