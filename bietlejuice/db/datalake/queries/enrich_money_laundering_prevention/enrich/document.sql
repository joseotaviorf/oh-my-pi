SELECT
    d.id AS id_document,
    d.id_folder,
    CASE
        WHEN id_folder_type = 2 THEN f.id_external
        ELSE NULL
    END AS id_house,
    CASE
        WHEN id_folder_type = 1 THEN f.id_external
        ELSE NULL
    END AS id_user,
    GET_JSON_OBJECT(fr.reference_properties, '$.offerId') AS id_offer,
    GET_JSON_OBJECT(fr.reference_properties, '$.proposalId') AS id_proposal,
    GET_JSON_OBJECT(fr.reference_properties, '$.proposalProponentId') AS id_proposal_proponent,
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
LEFT JOIN datalake_docx_clean.folder AS f
    ON d.id_folder = f.id
LEFT JOIN datalake_docx_clean.folder_reference AS fr
    ON fr.id_source_folder = f.id
    AND fr.reference_properties IS NOT NULL