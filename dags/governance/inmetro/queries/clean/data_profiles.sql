SELECT
    repo,
    CASE
        WHEN repo = "wonka" THEN "feature_sets"
        WHEN substr(database, -4) = "_raw" THEN "raw"
        WHEN substr(database, -6) = "_clean" THEN "clean"
        WHEN substr(database, 1, 10) = "dw_staging" THEN "dw_staging"
        ELSE "enrich"
    END AS layer,
    database,
    table,
    inmetro_info,
    year,
    month,
    day
FROM
    datalake_inmetro_raw.data_profiles
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
