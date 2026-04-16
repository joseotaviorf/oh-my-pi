SELECT
    id,
    email,
    username,
    first_name,
    last_name,
    is_active,
    is_staff,
    is_superuser,
    role,
    last_login AS ts_last_login,
    date_joined AS ts_joined,
    profile_img,
    NOW() AS ts_load
FROM
    datalake_legaut_raw.accounts_user
