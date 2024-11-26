SELECT
    id,
    proposal_id AS id_proposal,
    report_id AS id_report,
    cpf,
    status,
    matrix_name,
    version,
    report_result,
    validations,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.documentation_report
