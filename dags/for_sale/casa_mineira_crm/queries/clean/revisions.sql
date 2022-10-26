SELECT 
    id, 
    revisionable_id AS id_revisionable,
    user_id AS id_user, 
    `key` AS revision_key,
    revisionable_type,
    old_value,
    new_value,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated 
FROM 
    datalake_casa_mineira_crm_raw.revisions