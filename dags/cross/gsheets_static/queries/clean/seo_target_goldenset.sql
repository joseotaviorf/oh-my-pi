SELECT
    year,
    month,
    CAST(date AS date) AS dt_date,
    'Target 2025' AS target_goldenset
FROM
    datalake_gsheets_raw.seo_target_goldenset
