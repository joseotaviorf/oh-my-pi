SELECT
    id,
    cpf,
    version,
    integration_provider,
    raw_data,
    attributes,
    created_at AS ts_created,
    updated_at AS ts_updated,
    CAST(year AS INT) AS year,
    CAST(month AS INT) AS month,
    CAST(day AS INT) AS day
FROM
    datalake_arquivo_confidencial_raw.integration_report
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
