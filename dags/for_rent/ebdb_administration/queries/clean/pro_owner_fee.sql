SELECT
    id,
    user_pro_owner_id AS id_user_pro_owner,
    adm_fee,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_ebdb_raw.proownerfee
