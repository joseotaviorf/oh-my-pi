SELECT
    code AS sk_country_code,
    CAST(id AS INTEGER) AS id_country,
    code AS country_code,
    name AS country_name,
    default_locale,
    default_timezone,
    ts_created,
    ts_updated,
    NOW () AS ts_load
FROM
    datalake_ebdb_clean.country
