SELECT
    CAST(id AS INTEGER) AS sk_country,
    CAST(id AS INTEGER) AS id_country,
    code AS country_code,
    name AS country_name,
    default_locale,
    default_timezone,
    ts_created,
    ts_updated,
    NOW() AS ts_load
FROM
    datalake_ebdb_clean.country
UNION ALL
SELECT
    -1 AS sk_country,
    NULL AS id_country,
    NULL AS country_code,
    NULL AS country_name,
    NULL AS default_locale,
    'UTC' AS default_timezone,
    NULL AS ts_created,
    NULL AS ts_updated,
    NOW() AS ts_load