select
    metadata.suite_name,
    layer,
    database,
    table,
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