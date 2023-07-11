SELECT DISTINCT
    DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd') AS id_snapshot,
    u.id AS id_user,
    u.id_country,
    'photographer' AS client_type,
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
    datalake_ebdb_clean.photographer_data AS pd
INNER JOIN
    datalake_ebdb_clean.user AS u
        ON u.id_photographer_data = pd.id
        AND pd.is_active IS TRUE
LEFT JOIN
    datalake_ebdb_clean.country AS ct
        ON ct.id = u.id_country
