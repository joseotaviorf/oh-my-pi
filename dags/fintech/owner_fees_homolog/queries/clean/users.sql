SELECT
    id,
    external_id AS id_external,
    name AS user_name,
    email AS user_email,
    phone AS user_phone,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_fees_homolog_raw.users
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
