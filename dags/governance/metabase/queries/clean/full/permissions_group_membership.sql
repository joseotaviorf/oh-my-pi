SELECT 
    id,
    group_id AS id_group,
    user_id AS id_user,
    is_group_manager
FROM datalake_metabase_raw.permissions_group_membership