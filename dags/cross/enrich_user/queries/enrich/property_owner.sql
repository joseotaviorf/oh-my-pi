SELECT DISTINCT
    u.id AS id_user,
    u.id_country,
    'property_owner' AS client_type,
    COALESCE(ct.code, 'Undefined') AS country_code,
    u.main_phone,
    u.name,
    u.email,
    u.is_active,
    u.is_blocked,
    DATE(u.dt_birth) AS dt_birth,
    u.ts_created AS ts_user_created,
    u.ts_updated AS ts_user_updated,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    datalake_ebdb_clean.house AS h
INNER JOIN
    datalake_ebdb_clean.user AS u
        ON u.id = h.id_user
        AND h.status IN (
          'alugado',
          'aguardando_publicacao',
          'edicao',
          'publicado',
          'suspenso'
        )
LEFT JOIN
    datalake_ebdb_clean.partner_agent AS pa
        ON h.id_user = pa.id_user
LEFT JOIN
    datalake_ebdb_clean.country AS ct
        ON ct.id = u.id_country
WHERE
    pa.id_user IS NULL
