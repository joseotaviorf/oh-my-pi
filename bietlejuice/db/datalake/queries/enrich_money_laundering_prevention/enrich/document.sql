SELECT
    d.id AS id_document,
    ce.id_proposal,
    dt.name AS document_type,
    d.attributes,
    d.attachments,
    dc.name AS document_context
FROM
    datalake_docx_clean.document AS d
JOIN datalake_docx_clean.document_context AS dc
    ON dc.id = d.id_document_context
JOIN datalake_docx_clean.document_type AS dt
    ON dt.id = d.id_document_type
LEFT JOIN datalake_docx_clean.credit_evaluation AS ce
    ON ce.id_proposal = d.id_context_external