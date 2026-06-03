SELECT
    id          AS id_user,
    name        AS user_name,
    email       AS user_email,
    github_user AS github_username,
    chapter     AS user_chapter
FROM
    datalake_devlake_raw.users
