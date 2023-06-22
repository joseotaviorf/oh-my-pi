SELECT
    id AS id_user,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    external_id AS id_external,
    external_id_mod AS mod_id_external,
    name,
    name_mod AS mod_name,
    email,
    email_mod AS mod_email,
    phone,
    phone_mod AS mod_phone,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_notify_me_raw.users_aud
WHERE
	DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')