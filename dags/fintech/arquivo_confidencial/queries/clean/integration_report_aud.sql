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
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.integration_report_aud
