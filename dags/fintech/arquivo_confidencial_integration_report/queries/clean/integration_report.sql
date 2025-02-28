SELECT
    id,
    cpf,
    version,
    integration_provider,
    raw_data,
    attributes,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.integration_report
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
