SELECT
    id,
    contract_analysis_request_id AS id_contract_analysis_request,
    document_attachment_id AS id_document_attachment,
    document_extraction_id AS id_document_extraction,
    download_started_at,
    download_ended_at,
    extraction_started_at,
    extraction_ended_at,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_legalops_raw.contract_analysis_data_relation
