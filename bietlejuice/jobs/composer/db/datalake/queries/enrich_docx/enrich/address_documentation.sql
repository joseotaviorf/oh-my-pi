SELECT
    id,
    id_folder,
    id_document_type,
    id_document_context,
    id_context_external,
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
    GET_JSON_OBJECT(attributes, '$.cep') AS zip_code,
    GET_JSON_OBJECT(attributes, '$.state') AS state,
    GET_JSON_OBJECT(attributes, '$.city') AS city,
    GET_JSON_OBJECT(attributes, '$.neighborhood') AS neighborhood,
    GET_JSON_OBJECT(attributes, '$.street') AS address,
    GET_JSON_OBJECT(attributes, '$.number') AS address_number,
    GET_JSON_OBJECT(attributes, '$.complement') AS address_complement,
    GET_JSON_OBJECT(attributes, '$.timeInCurrentResidenceInYears') AS years_in_current_residence,
    GET_JSON_OBJECT(attributes, '$.currentLivingSituation') AS current_living_situation,
    GET_JSON_OBJECT(attributes, '$.realEstateOrOwnerName') AS real_estate_or_owner_name,
    GET_JSON_OBJECT(attributes, '$.realEstateOrOwnerPhone') AS real_estate_or_owner_phone_number,
    NULLIF(attachments, '[]') AS attributes,
    NULLIF(attachments, '[]') AS attachments,
    ts_created,
    ts_updated
FROM
    datalake_docx_clean.document
WHERE
    id_document_type = 13