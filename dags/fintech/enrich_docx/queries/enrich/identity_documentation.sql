WITH get_personal_data AS (
  SELECT
    d.id_folder,
    d.id_context_external,
    ft.name AS folder_type,
    GET_JSON_OBJECT(d.attributes, '$.cpf') AS cpf
  FROM
    datalake_docx_clean.document AS d
  INNER JOIN datalake_docx_clean.folder AS f ON d.id_folder = f.id
  INNER JOIN datalake_docx_clean.folder_type AS ft ON ft.id = f.id_folder_type
  WHERE d.id_document_type = 7
)

SELECT
    d.id AS id_document,
    d.id_folder,
    d.id_document_type,
    CAST(d.id_context_external AS bigint) AS id_proposal,
    GET_JSON_OBJECT(d.attributes, '$.documentNumber') AS document_number,
    pd.cpf,
    dt.name AS document_type,
    dc.name AS document_context,
    pd.folder_type,
    GET_JSON_OBJECT(d.attributes, '$.motherName') AS mother_name,
    GET_JSON_OBJECT(d.attributes, '$.nationality') AS nationality,
    GET_JSON_OBJECT(d.attributes, '$.countryOfOrigin') AS country_of_origin,
    d.attributes,
    d.attachments,
    DATE(GET_JSON_OBJECT(d.attributes, '$.birthDate')) AS dt_birth,
    CAST(GET_JSON_OBJECT(d.attributes, '$.isNewRg') AS boolean) AS is_new_rg,
    CAST(GET_JSON_OBJECT(d.attributes, '$.isDigital') AS boolean) AS is_digital,
    d.ts_created,
    d.ts_updated
FROM
    datalake_docx_clean.document AS d
INNER JOIN
    datalake_docx_clean.document_type AS dt
        ON d.id_document_type = dt.id
INNER JOIN
    datalake_docx_clean.document_context AS dc
        ON d.id_document_context = dc.id
LEFT JOIN
    get_personal_data AS pd
        ON pd.id_folder = d.id_folder
        AND pd.id_context_external = d.id_context_external
WHERE
    d.id_document_type IN (1, 2, 3, 4)
