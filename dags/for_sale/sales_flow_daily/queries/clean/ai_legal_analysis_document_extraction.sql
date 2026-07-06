SELECT
    id,
    sales_flow_id AS id_sales_flow,
    docx_attachment_document_id AS id_docx_attachment_document,
    docpilot_document_external_id AS id_docpilot_document_external,
    docx_attachment_filename,
    docpilot_document_extractor_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ai_legal_analysis_document_extraction


