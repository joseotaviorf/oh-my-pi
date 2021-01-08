SELECT
    user_id AS id_user,
    rev,
    revtstmp AS ts_rev
FROM 
    datalake_owner_fees_raw.user_rev_info
