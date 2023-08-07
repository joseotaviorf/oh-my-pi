select
    repo,
    case
        when repo = "wonka" then "feature_sets"
        when substr(database, -4) = "_raw" then "raw"
        when substr(database, -6) = "_clean" then "clean"
        when substr(database, 1, 3) = "dw_" and substr(database, -8) = "_staging" then "dw_staging"
        when substr(database, 1, 7) = "metric_" then "metric"
        else "enrich"
    end as layer,
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
    timestamp(metadata.run_date) AS ts_execution_utc,
    FROM_UTC_TIMESTAMP(metadata.run_date, 'America/Sao_Paulo') AS ts_execution_local,
    year,
    month,
    day
from
    datalake_inmetro_raw.data_validations
where
    year = {year}
    and month = {month}
    and day = {day}
