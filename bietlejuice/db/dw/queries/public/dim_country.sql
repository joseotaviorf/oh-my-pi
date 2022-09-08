SELECT
    COALESCE(CAST(id AS INTEGER), -1) AS sk_country,
    CAST(id AS INTEGER) AS id_country,
    code AS country_code,
    name AS country_name,
    default_locale,
    COALESCE(default_timezone, 'UTC') AS default_timezone,
    ts_created,
    ts_updated,
    NOW() AS ts_load
FROM
    datalake_ebdb_clean.country