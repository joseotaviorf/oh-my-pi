SELECT 
    id,
    created_by_fk AS id_user_created,
    changed_by_fk AS id_user_changed,
    first_name,
    last_name,
    username,
    password,
    email,
    active AS is_active,
    login_count,
    fail_login_count,
    created_on AS ts_created,
    changed_on AS ts_changed,
    last_login AS ts_last_login,
    year,
    month,
    day
FROM
    datalake_superset_raw.ab_user
WHERE MAKE_DATE(year, month, day) BETWEEN {load_start_date} AND {load_end_date}