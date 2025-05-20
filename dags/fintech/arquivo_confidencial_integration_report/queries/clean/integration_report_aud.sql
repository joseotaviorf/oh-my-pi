SELECT
    id,
    cpf,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    integration_provider,
    raw_data,
    attributes,
    created_at AS ts_created,
    CAST(year AS INT) AS year,
    CAST(month AS INT) AS month,
    CAST(day AS INT) AS day
FROM
    datalake_arquivo_confidencial_raw.integration_report_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
