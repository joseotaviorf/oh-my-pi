SELECT
    SHA2(id_user, 256)  AS sk_user,
    id_user,
    user_name,
    user_email,
    github_username,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_devlake_clean.users
