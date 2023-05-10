SELECT DISTINCT
    u.id AS id_user,
    u.id_country,
    'tenant' AS client_type,
    COALESCE(ct.code, 'Undefined') AS country_code,
    u.main_phone,
    u.name,
    u.email,
    u.cpf,
    u.is_active,
    u.is_blocked,
    DATE(u.dt_birth) AS dt_birth,
    u.ts_created AS ts_user_created,
    u.ts_updated AS ts_user_updated,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    datalake_ebdb_clean.user AS u
INNER JOIN
    datalake_ebdb_clean.contract AS c
        ON c.id_user = u.id
        AND c.status = 'Ativo'
LEFT JOIN
    datalake_ebdb_clean.country AS ct
        ON ct.id = u.id_country
