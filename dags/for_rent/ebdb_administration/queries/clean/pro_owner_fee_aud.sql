SELECT
    id,
    user_pro_owner_id AS id_user_pro_owner,
    rev,
    revtype,
    adm_fee,
    active AS is_active,
    user_pro_owner_id_mod AS mod_id_user_pro_owner,
    adm_fee_mod AS mod_adm_fee,
    active_mod AS mod_is_active
FROM 
    datalake_ebdb_raw.proownerfee_aud
