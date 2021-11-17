SELECT 
    CAST(id AS INT) AS id,
    CAST(user_id AS BIGINT) AS id_user,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_ebdb_raw.userproowner