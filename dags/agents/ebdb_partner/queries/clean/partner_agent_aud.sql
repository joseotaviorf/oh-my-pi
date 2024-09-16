SELECT
    id,
    partner_id AS id_partner,
    user_id AS id_user,
    REV AS rev,
    REVTYPE AS rev_type, 
    status,
    type,
    partner_MOD AS mod_partner,
    status_MOD AS mod_status,
    type_MOD AS mod_type
FROM
    datalake_ebdb_test_raw.partneragent_aud
