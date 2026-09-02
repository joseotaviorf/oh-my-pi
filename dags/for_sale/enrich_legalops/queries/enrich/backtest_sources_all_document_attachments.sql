WITH documents_attachments AS (
  SELECT DISTINCT
    'SALES_FLOW' AS document_source,
    sales_flows_screenings.id_sales_flow,
    CAST(NULL AS BIGINT) AS id_seller,
    CAST(NULL AS BIGINT) AS id_buyer,
    CONCAT(
      'https://apigw.prod.quintoandar.com.br/docx-api/v2/intra/attachments/',
      attachment_struct['fileName'],
      '?documentId=',
      CAST(d.id AS STRING)
    ) AS docx_attachment_prod_url,
    REGEXP_EXTRACT(
      attachment_struct['fileName'],
      '([a-f0-9]{{8}}-(?:[a-f0-9]{{4}}-){{3}}[a-f0-9]{{12}})',
      1
    ) AS attachment_guid,
    attachment_struct['fileName'] AS attachment_filename,
    d.ts_created AS document_ts_created,
    dt.name AS document_type_name,
    d.id AS id_document,
    TRY_CAST(attachment_struct['pageNumber'] AS INT) AS pageNumber,
    d.attributes AS document_attributes
  FROM
    datalake_legalops.backtest_sources_sales_flows_screenings AS sales_flows_screenings
  LEFT JOIN
    datalake_docx_clean.folder AS f
      ON sales_flows_screenings.ScreeningCCV__property_id = f.id_external
  LEFT JOIN
    datalake_docx_clean.document AS d
      ON f.id = d.id_folder
  LEFT JOIN
    datalake_docx_clean.document_type AS dt
      ON d.id_document_type = dt.id
  LATERAL VIEW OUTER POSEXPLODE(
    FROM_JSON(d.attachments, 'ARRAY<MAP<STRING, STRING>>')
  ) exploded_table AS position, attachment_struct

  UNION ALL

  SELECT DISTINCT
    'SELLER_DATA' AS document_source,
    seller_data.id_sales_flow,
    seller_data.id_seller AS id_seller,
    CAST(NULL AS BIGINT) AS id_buyer,
    CONCAT(
      'https://apigw.prod.quintoandar.com.br/docx-api/v2/intra/attachments/',
      attachment_struct['fileName'],
      '?documentId=',
      CAST(d.id AS STRING)
    ) AS docx_attachment_prod_url,
    REGEXP_EXTRACT(
      attachment_struct['fileName'],
      '([a-f0-9]{{8}}-(?:[a-f0-9]{{4}}-){{3}}[a-f0-9]{{12}})',
      1
    ) AS attachment_guid,
    attachment_struct['fileName'] AS attachment_filename,
    d.ts_created AS document_ts_created,
    dt.name AS document_type_name,
    d.id AS id_document,
    TRY_CAST(attachment_struct['pageNumber'] AS INT) AS pageNumber,
    d.attributes AS document_attributes
  FROM
    datalake_sales_flow_clean.seller_data AS seller_data
  LEFT JOIN
    datalake_docx_clean.folder AS f
      ON seller_data.id_docx_folder = f.id
  LEFT JOIN
    datalake_docx_clean.document AS d
      ON f.id = d.id_folder
  LEFT JOIN
    datalake_docx_clean.document_type AS dt
      ON d.id_document_type = dt.id
  LATERAL VIEW OUTER POSEXPLODE(
    FROM_JSON(d.attachments, 'ARRAY<MAP<STRING, STRING>>')
  ) exploded_table AS position, attachment_struct

  UNION ALL

  SELECT DISTINCT
    'BUYER_DATA' AS document_source,
    buyer_data.id_sales_flow,
    CAST(NULL AS BIGINT) AS id_seller,
    buyer_data.id_buyer AS id_buyer,
    CONCAT(
      'https://apigw.prod.quintoandar.com.br/docx-api/v2/intra/attachments/',
      attachment_struct['fileName'],
      '?documentId=',
      CAST(d.id AS STRING)
    ) AS docx_attachment_prod_url,
    REGEXP_EXTRACT(
      attachment_struct['fileName'],
      '([a-f0-9]{{8}}-(?:[a-f0-9]{{4}}-){{3}}[a-f0-9]{{12}})',
      1
    ) AS attachment_guid,
    attachment_struct['fileName'] AS attachment_filename,
    d.ts_created AS document_ts_created,
    dt.name AS document_type_name,
    d.id AS id_document,
    TRY_CAST(attachment_struct['pageNumber'] AS INT) AS pageNumber,
    d.attributes AS document_attributes
  FROM
    datalake_sales_flow_clean.buyer_data AS buyer_data
  LEFT JOIN
    datalake_docx_clean.folder AS f
      ON buyer_data.id_docx_folder = f.id
  LEFT JOIN
    datalake_docx_clean.document AS d
      ON f.id = d.id_folder
  LEFT JOIN
    datalake_docx_clean.document_type AS dt
      ON d.id_document_type = dt.id
  LATERAL VIEW OUTER POSEXPLODE(
    FROM_JSON(d.attachments, 'ARRAY<MAP<STRING, STRING>>')
  ) exploded_table AS position, attachment_struct
),

all_sales_flow_with_document_attachments AS (
  SELECT
    sales_flows_screenings.id_sales_flow,
    documents_attachments.document_source,
    documents_attachments.id_seller,
    documents_attachments.id_buyer,
    documents_attachments.docx_attachment_prod_url,
    documents_attachments.attachment_guid,
    documents_attachments.attachment_filename,
    documents_attachments.document_ts_created,
    documents_attachments.document_type_name,
    documents_attachments.id_document,
    documents_attachments.pageNumber,
    documents_attachments.document_attributes
  FROM
    datalake_legalops.backtest_sources_sales_flows_screenings AS sales_flows_screenings
  LEFT JOIN
    documents_attachments
      ON sales_flows_screenings.id_sales_flow = documents_attachments.id_sales_flow
),

add_doc_kind AS (
  SELECT
    id_sales_flow,
    id_seller,
    id_buyer,
    id_document,
    docx_attachment_prod_url,
    attachment_filename,
    attachment_guid,
    CASE
      WHEN ROW_NUMBER() OVER (
        PARTITION BY id_sales_flow
        ORDER BY
          CASE
            WHEN pageNumber = 0
              AND document_attributes IS NOT NULL
              AND document_type_name IN (
                'HOUSE_REGISTRATION',
                'HOUSE_REGISTRATION_UPDATED'
              )
            THEN document_ts_created
            ELSE NULL
          END DESC
      ) = 1
        AND pageNumber = 0
        AND document_attributes IS NOT NULL
        AND document_type_name IN (
          'HOUSE_REGISTRATION',
          'HOUSE_REGISTRATION_UPDATED'
        )
      THEN 'HOUSE_REGISTRATION'
      WHEN pageNumber IN (1000, 1001)
        AND document_type_name IN (
          'HOUSE_REGISTRATION',
          'HOUSE_REGISTRATION_UPDATED'
        )
      THEN 'HOUSE_REGISTRATION_OCR_EXTRACT'
      WHEN pageNumber BETWEEN 1 AND 999
        AND document_type_name IN (
          'HOUSE_REGISTRATION',
          'HOUSE_REGISTRATION_UPDATED'
        )
      THEN 'HOUSE_EXTRA_REGISTRATION_ATTACHMENT'
      WHEN document_source IN ('BUYER_DATA', 'SELLER_DATA')
        AND document_type_name = 'PERSONAL_DATA'
        AND pageNumber = 1
      THEN 'MARITAL_CERTIFICATE_FRONT'
      WHEN document_source IN ('BUYER_DATA', 'SELLER_DATA')
        AND document_type_name = 'PERSONAL_DATA'
        AND pageNumber = 2
      THEN 'MARITAL_CERTIFICATE_BACK'
      WHEN document_source IN ('BUYER_DATA', 'SELLER_DATA')
        AND document_type_name = 'PERSONAL_DATA'
        AND pageNumber = 3
      THEN 'STABLE_UNION_CERTIFICATE_FRONT'
      WHEN document_source IN ('BUYER_DATA', 'SELLER_DATA')
        AND document_type_name = 'PERSONAL_DATA'
        AND pageNumber = 4
      THEN 'STABLE_UNION_CERTIFICATE_BACK'
      WHEN document_source IN ('BUYER_DATA', 'SELLER_DATA')
        AND document_type_name IN ('RG', 'CNH')
        AND pageNumber = 1
      THEN 'PERSONAL_IDENTIFICATION_FRONT'
      WHEN document_source IN ('BUYER_DATA', 'SELLER_DATA')
        AND document_type_name IN ('RG', 'CNH')
        AND pageNumber = 2
      THEN 'PERSONAL_IDENTIFICATION_BACK'
      WHEN document_source IN ('BUYER_DATA', 'SELLER_DATA')
        AND document_type_name IN ('RG', 'CNH')
        AND pageNumber = 4
      THEN 'PERSONAL_IDENTIFICATION_SELFIE'
      WHEN document_type_name = 'PROOF_OF_PROPERTY_REGISTRY'
      THEN 'PROOF_OF_PROPERTY_REGISTRY'
      WHEN document_type_name = 'HOUSE_REGISTRATION'
        AND pageNumber >= 1
      THEN 'ADDITIONAL_HOUSE_REGISTRATION'
      ELSE '(UNCLASSIFIED)'
    END AS doc_kind
  FROM
    all_sales_flow_with_document_attachments
)

SELECT
  id_sales_flow,
  id_seller,
  id_buyer,
  id_document,
  doc_kind,
  docx_attachment_prod_url,
  attachment_filename,
  attachment_guid
FROM
  add_doc_kind
WHERE
  attachment_filename IS NOT NULL
