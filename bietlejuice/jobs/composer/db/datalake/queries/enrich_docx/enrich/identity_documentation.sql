SELECT
    id,
    id_folder,
    id_document_type,
    id_document_context,
    id_context_external,
    GET_JSON_OBJECT(attributes, '$.documentNumber') AS document_number,
    CASE
        WHEN id_document_type = 1 THEN 'RG'
        WHEN id_document_type = 2 THEN 'CPF'
        WHEN id_document_type = 3 THEN 'CNH'
        WHEN id_document_type = 4 THEN 'RNE'
    END AS document_type,
    CASE
        WHEN id_document_context = 1 THEN 'Owner'
        WHEN id_document_context = 2 THEN 'Tenant'
        WHEN id_document_context = 3 THEN 'Affiliate'
        WHEN id_document_context = 4 THEN 'Buyer'
        WHEN id_document_context = 5 THEN 'Seller'
    END AS document_context,
    GET_JSON_OBJECT(attributes, '$.motherName') AS mother_name,
    GET_JSON_OBJECT(attributes, '$.nationality') AS nationality,
    GET_JSON_OBJECT(attributes, '$.countryOfOrigin') AS country_of_origin,
    NULLIF(attachments, '[]') AS attributes,
    NULLIF(attachments, '[]') AS attachments,
    DATE(GET_JSON_OBJECT(attributes, '$.birthDate')) AS dt_birth,
    ts_created,
    ts_updated
FROM
    datalake_docx_clean.document
WHERE
    id_document_type IN (1, 3, 4)