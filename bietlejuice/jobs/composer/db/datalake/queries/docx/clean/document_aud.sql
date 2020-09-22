SELECT
    id,
    folder_id AS id_folder,
    document_context_id AS id_document_context,
    context_external_id AS id_context_external,
    document_type_id AS id_document_type,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    attributes,
    attachments
FROM datalake_docx_raw.document_aud
