SELECT DISTINCT
    COALESCE(id_user,-1)                             AS sk_consultant,
    user_name || ' ' || user_last_name  AS consultant_name,
    user_email                          AS consultant_email
FROM
    datalake_atta_clean.users_info
