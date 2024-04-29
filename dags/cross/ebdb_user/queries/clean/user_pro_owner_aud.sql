SELECT 
    CAST(id AS INT) AS id,
    CAST(user_id AS BIGINT) AS id_user,
    CAST(account_manager_id AS BIGINT) AS id_account_manager,
    REV AS rev,
    REVTYPE as rev_type,
    active AS is_active,
    account_manager_id_MOD AS mod_id_account_manager,
    active_MOD AS mod_is_active
FROM 
    datalake_ebdb_raw.userproowner_aud