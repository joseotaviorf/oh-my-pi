SELECT
    id,
    cpf,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    presumed_income,
    source,
    attributes
FROM
    datalake_arquivo_confidencial_raw.presumed_income_report_aud