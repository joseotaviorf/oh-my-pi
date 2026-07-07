SELECT
    NULLIF(email, '') AS email,
    NULLIF(special_role, '') AS special_role,
    NOW() AS ts_load
FROM
    datalake_gsheets_people_raw.turnover_user_roles
WHERE
    email IS NOT NULL
    AND email <> ''
