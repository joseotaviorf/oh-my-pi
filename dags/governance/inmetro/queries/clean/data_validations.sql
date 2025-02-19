SELECT
    repo,
    CASE
        WHEN repo = "wonka" THEN "feature_sets"
        WHEN substr(database, -4) = "_raw" THEN "raw"
        WHEN substr(database, -6) = "_clean" THEN "clean"
        WHEN substr(database, 1, 3) = "dw_" AND substr(database, -8) = "_staging" THEN "dw_staging"
        WHEN substr(database, 1, 7) = "metric_" THEN "metric"
        ELSE "enrich"
    END AS layer,
    database,
    table,
    metadata.suite_name,
    LCASE(metadata.suite_result) AS suite_result,
    metadata.validations_count,
    metadata.success AS success_count,
    metadata.failure AS failure_count,
    metadata.success_rate,
    TO_JSON(metadata) AS metadata,
    TO_JSON(validations) AS validations,
    TIMESTAMP(metadata.run_date) AS ts_execution_utc,
    FROM_UTC_TIMESTAMP(metadata.run_date, 'America/Sao_Paulo') AS ts_execution_local,
    year,
    month,
    day
FROM
    datalake_inmetro_raw.data_validations
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
