WITH 
  -- Documents from SALES_FLOW (property-level documents)
  sales_flow_documents AS (
    SELECT DISTINCT
      'SALES_FLOW' AS document_source,
      sales_flows_screenings.id_sales_flow,
      CAST(NULL AS BIGINT) AS id_seller,
      CAST(NULL AS BIGINT) AS id_buyer,
      d.id as id_document,
      d.attributes as document_attributes,
      dt.name as document_type_name,
      dc.name as document_context_name,
      d.ts_created as document_ts_created
    FROM
      datalake_legalops.backtest_sources_sales_flows_screenings as sales_flows_screenings
      INNER JOIN datalake_docx_clean.folder AS f 
        ON sales_flows_screenings.ScreeningCCV__property_id = f.id_external
      LEFT JOIN datalake_docx_clean.document AS d 
        ON f.id = d.id_folder
      LEFT JOIN datalake_docx_clean.document_type AS dt 
        ON d.id_document_type = dt.id
      LEFT JOIN datalake_docx_clean.document_context AS dc 
        ON d.id_document_context = dc.id
    WHERE d.attributes IS NOT NULL
  ),

  -- Documents from SELLER_DATA (seller-level documents)
  seller_documents AS (
    SELECT DISTINCT
      'SELLER_DATA' AS document_source,
      seller_data.id_sales_flow,
      seller_data.id_seller AS id_seller,
      CAST(NULL AS BIGINT) AS id_buyer,
      d.id as id_document,
      d.attributes as document_attributes,
      dt.name as document_type_name,
      dc.name as document_context_name,
      d.ts_created as document_ts_created
    FROM
      datalake_legalops.backtest_sources_sales_flows_screenings as sales_flows_screenings
      INNER JOIN datalake_sales_flow_clean.seller_data AS seller_data
        ON sales_flows_screenings.id_sales_flow = seller_data.id_sales_flow
      LEFT JOIN datalake_docx_clean.folder AS f 
        ON seller_data.id_docx_folder = f.id
      LEFT JOIN datalake_docx_clean.document AS d 
        ON f.id = d.id_folder
      LEFT JOIN datalake_docx_clean.document_type AS dt 
        ON d.id_document_type = dt.id
      LEFT JOIN datalake_docx_clean.document_context AS dc 
        ON d.id_document_context = dc.id
    WHERE d.attributes IS NOT NULL
  ),

  -- Documents from BUYER_DATA (buyer-level documents)
  buyer_documents AS (
    SELECT DISTINCT
      'BUYER_DATA' AS document_source,
      buyer_data.id_sales_flow,
      CAST(NULL AS BIGINT) AS id_seller,
      buyer_data.id_buyer AS id_buyer,
      d.id as id_document,
      d.attributes as document_attributes,
      dt.name as document_type_name,
      dc.name as document_context_name,
      d.ts_created as document_ts_created
    FROM
      datalake_legalops.backtest_sources_sales_flows_screenings as sales_flows_screenings
      INNER JOIN datalake_sales_flow_clean.buyer_data AS buyer_data
        ON sales_flows_screenings.id_sales_flow = buyer_data.id_sales_flow
      LEFT JOIN datalake_docx_clean.folder AS f 
        ON buyer_data.id_docx_folder = f.id
      LEFT JOIN datalake_docx_clean.document AS d 
        ON f.id = d.id_folder
      LEFT JOIN datalake_docx_clean.document_type AS dt 
        ON d.id_document_type = dt.id
      LEFT JOIN datalake_docx_clean.document_context AS dc 
        ON d.id_document_context = dc.id
    WHERE d.attributes IS NOT NULL
  ),

  all_documents AS (
    SELECT
      document_source,
      id_sales_flow,
      id_seller,
      id_buyer,
      id_document,
      document_attributes,
      document_type_name,
      document_context_name,
      document_ts_created
    FROM
      sales_flow_documents
    UNION ALL
    SELECT
      document_source,
      id_sales_flow,
      id_seller,
      id_buyer,
      id_document,
      document_attributes,
      document_type_name,
      document_context_name,
      document_ts_created
    FROM
      seller_documents
    UNION ALL
    SELECT
      document_source,
      id_sales_flow,
      id_seller,
      id_buyer,
      id_document,
      document_attributes,
      document_type_name,
      document_context_name,
      document_ts_created
    FROM
      buyer_documents
  )

SELECT
  document_source,
  id_sales_flow,
  id_seller,
  id_buyer,
  id_document,
  document_type_name,
  document_context_name,
  document_ts_created,
  attribute_key,
  attribute_value
FROM
  all_documents
  LATERAL VIEW OUTER EXPLODE(
    FROM_JSON(document_attributes, 'MAP<STRING, STRING>')
  ) exploded_table AS attribute_key, attribute_value
WHERE 
  (
    document_type_name = 'HOUSE_REGISTRATION'
    AND attribute_key IN ('registryNumber', 'registryOffice', 'houseTaxpayerCode', 'hasExtraRegistry', 'hasUsedFgtsToBuy', 'hasRecentTransaction', 'hasTransactionInFamily', 'howLongHasAcquired', 'city', 'description', 'acquisitionType', 'hasEnvironmentalOrZoningRestrictions')
  )
  OR
(
  document_type_name = 'HOUSE_OWNERSHIP_PROOF'
  AND attribute_key IN ('isSellerOnRegistry')
)
  OR 
  (
    document_type_name = 'BANK_DATA'
    AND attribute_key IN ('isPj', 'willReceiveSaleValue')
  )
  OR 
  (
    document_type_name = 'PERSONAL_DATA'
    AND attribute_key IN ('isRepresentedByAttorney', 'isHouseHolder')
  )
ORDER BY
  id_sales_flow,
  document_source,
  id_document