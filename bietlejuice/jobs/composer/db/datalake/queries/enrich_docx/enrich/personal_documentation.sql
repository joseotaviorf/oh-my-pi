SELECT
    id,
    id_folder,
    id_document_type,
    id_document_context,
    id_context_external,
    GET_JSON_OBJECT(attributes, '$.cpf') AS cpf,
    CASE
        WHEN id_document_type = 1 THEN 'RG'
        WHEN id_document_type = 2 THEN 'CPF'
        WHEN id_document_type = 3 THEN 'CNH'
        WHEN id_document_type = 4 THEN 'RNE'
        WHEN id_document_type = 7 THEN 'PERSONAL_DATA'
        WHEN id_document_type = 11 THEN 'INCOME_DATA'
        WHEN id_document_type = 13 THEN 'ADDRESS'
    END AS document_type,
    CASE
        WHEN id_document_context = 1 THEN 'Owner'
        WHEN id_document_context = 2 THEN 'Tenant'
        WHEN id_document_context = 3 THEN 'Affiliate'
        WHEN id_document_context = 4 THEN 'Buyer'
        WHEN id_document_context = 5 THEN 'Seller'
    END AS document_context,
    GET_JSON_OBJECT(attributes, '$.fullName') AS full_name,
    GET_JSON_OBJECT(attributes, '$.email') AS email,
    GET_JSON_OBJECT(attributes, '$.telephone') AS telephone_number,
    GET_JSON_OBJECT(attributes, '$.cellPhone') AS cell_phone_number,
    GET_JSON_OBJECT(attributes, '$.maritalStatus') AS marital_status,
    GET_JSON_OBJECT(attributes, '$.rentReason') AS rent_reason,
    NULLIF(attachments, '[]') AS attributes,
    NULLIF(attachments, '[]') AS attachments,
    BOOLEAN(GET_JSON_OBJECT(attributes, '$.willReside')) AS will_reside,
    ts_created,
    ts_updated
FROM
    datalake_docx_clean.document
WHERE
    id_document_type = 7