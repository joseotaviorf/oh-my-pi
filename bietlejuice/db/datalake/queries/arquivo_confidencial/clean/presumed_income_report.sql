SELECT
    id,
    cpf,
    presumed_income,
    source,
    attributes,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_arquivo_confidencial_raw.presumed_income_report