SELECT
    id,
    proposal_id AS id_proposal,
    report_id AS id_report,
    cpf,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    status,
    matrix_name,
    report_result,
    validations,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.documentation_report_aud
