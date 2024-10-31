SELECT 
    CAST(id AS INT) AS id,
    user_id AS id_user,
    account_manager_id AS id_account_manager,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_ebdb_raw.userproowner