SELECT
    year,
    month,
    TO_DATE(`date`, 'dd/MM/yyyy') as dt_date,
    'Target 2025' AS target_goldenset
FROM
    datalake_gsheets_raw.seo_target_goldenset
