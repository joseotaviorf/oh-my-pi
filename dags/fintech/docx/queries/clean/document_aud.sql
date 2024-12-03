SELECT
    id,
    folder_id AS id_folder,
    document_context_id AS id_document_context,
    context_external_id AS id_context_external,
    document_type_id AS id_document_type,
    country_code,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    attributes,
    attachments,
    country_code_mod AS mod_country_code
FROM
    datalake_docx_raw.document_aud
