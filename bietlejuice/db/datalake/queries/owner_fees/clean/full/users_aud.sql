SELECT
    id AS id_user,
    external_id AS id_external,
    name AS user_name,
    email AS user_email,
    phone AS user_phone,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_owner_fees_raw.users_aud
