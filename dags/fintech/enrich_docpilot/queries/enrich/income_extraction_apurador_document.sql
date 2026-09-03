WITH doc_base AS (
  SELECT
    document.id AS id_income_extraction_document,
    document.id_batch,
    CAST(batch.id_external AS BIGINT) AS id_external,
    batch.external_source,
    batch.status AS apurador_batch_status,
    batch.error_type AS apurador_batch_error_type,
    document.id_platform_document,
    document.file_path,
    document.classified_document_type,
    document.extraction_result,
    document.inclusion_result,
    document.error AS apurador_document_error,
    document.ts_created AS ts_document_created
  FROM
    datalake_docpilot_clean.income_extraction_document AS document
  LEFT JOIN
    datalake_docpilot_clean.income_extraction_batch AS batch
      ON document.id_batch = batch.id
),
platform_doc AS (
  SELECT
    id AS id_platform_internal,
    id_document_external,
    application_name AS platform_application_name,
    context AS platform_context,
    original_document_uri AS platform_original_uri,
    internal_document_uri AS platform_internal_uri,
    document_metadata AS platform_document_metadata_json,
    checksum AS platform_checksum,
    ts_created AS ts_platform_doc_created
  FROM
    datalake_docpilot_platform_clean.document
),
platform_ext_latest AS (
  SELECT
    id_document,
    platform_extractor_name,
    platform_extractor_type,
    platform_extraction_status,
    platform_extraction_error,
    platform_extracted_data_json,
    platform_extractor_metadata_json,
    platform_retry_count,
    ts_platform_ext_created,
    ts_platform_ext_processed
  FROM (
    SELECT
      id_document,
      extractor_name AS platform_extractor_name,
      document_extractor_type AS platform_extractor_type,
      status AS platform_extraction_status,
      error AS platform_extraction_error,
      extracted_data AS platform_extracted_data_json,
      extractor_metadata AS platform_extractor_metadata_json,
      retry_count AS platform_retry_count,
      ts_created AS ts_platform_ext_created,
      ts_processed AS ts_platform_ext_processed,
      ROW_NUMBER() OVER (
        PARTITION BY id_document
        ORDER BY
          CASE
            WHEN status = 'COMPLETED' THEN 0
            ELSE 1
          END,
          ts_processed DESC NULLS LAST,
          ts_created DESC
      ) AS rn
    FROM
      datalake_docpilot_platform_clean.extraction
  ) AS ranked_platform_extractions
  WHERE
    rn = 1
),
legacy_latest AS (
  SELECT
    CAST(id_external AS BIGINT) AS id_external,
    legacy_external_source,
    processing_result AS legacy_processing_result,
    documents_type AS legacy_documents_type
  FROM (
    SELECT
      id_external,
      external_source AS legacy_external_source,
      processing_result,
      documents_type,
      ROW_NUMBER() OVER (
        PARTITION BY id_external, external_source
        ORDER BY ts_updated DESC, ts_created DESC
      ) AS rn
    FROM
      datalake_docpilot_clean.income_extraction
  ) AS ranked_legacy_extractions
  WHERE
    rn = 1
)
SELECT
  doc_base.id_income_extraction_document,
  doc_base.id_batch,
  doc_base.id_external,
  doc_base.id_platform_document,
  platform_doc.id_platform_internal,
  doc_base.external_source,
  doc_base.apurador_batch_status,
  doc_base.apurador_batch_error_type,
  doc_base.file_path,
  doc_base.classified_document_type,
  doc_base.extraction_result,
  doc_base.inclusion_result,
  doc_base.apurador_document_error,
  platform_doc.platform_application_name,
  platform_doc.platform_context,
  platform_doc.platform_original_uri,
  platform_doc.platform_internal_uri,
  platform_doc.platform_document_metadata_json,
  platform_doc.platform_checksum,
  platform_ext_latest.platform_extractor_name,
  platform_ext_latest.platform_extractor_type,
  platform_ext_latest.platform_extraction_status,
  platform_ext_latest.platform_extraction_error,
  platform_ext_latest.platform_extracted_data_json,
  platform_ext_latest.platform_extractor_metadata_json,
  legacy_latest.legacy_processing_result,
  legacy_latest.legacy_documents_type,
  COALESCE(
    GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.account_holder'),
    GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.taxpayer_name'),
    GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.employee_name'),
    GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.payslips[0].employee_name')
  ) AS platform_holder_name,
  CAST(
    COALESCE(
      GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.payslips[0].net_pay'),
      GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.gross_salary'),
      GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.taxable_income'),
      GET_JSON_OBJECT(
        platform_ext_latest.platform_extracted_data_json,
        '$.months[0].gross_monthly_income'
      ),
      GET_JSON_OBJECT(
        platform_ext_latest.platform_extracted_data_json,
        '$.months[0].total_invested_balance'
      )
    ) AS DECIMAL(18, 2)
  ) AS platform_balance,
  platform_ext_latest.platform_retry_count,
  platform_doc.id_platform_internal IS NOT NULL AS has_platform_document,
  platform_ext_latest.id_document IS NOT NULL AS has_platform_extraction,
  COALESCE(
    GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.statement_start_date'),
    GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.contract_start_date'),
    CAST(
      GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.calendar_year') AS STRING
    ),
    GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.payslips[0].reference_period')
  ) AS dt_platform_start,
  COALESCE(
    GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.statement_end_date'),
    GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.term_end_date'),
    CAST(
      GET_JSON_OBJECT(platform_ext_latest.platform_extracted_data_json, '$.calendar_year') AS STRING
    )
  ) AS dt_platform_end,
  doc_base.ts_document_created,
  platform_doc.ts_platform_doc_created,
  platform_ext_latest.ts_platform_ext_created,
  platform_ext_latest.ts_platform_ext_processed,
  NOW() AS ts_load
FROM
  doc_base
LEFT JOIN
  platform_doc
    ON LOWER(doc_base.id_platform_document) = LOWER(platform_doc.id_document_external)
    AND platform_doc.platform_context = 'DOCPILOT_INCOME_EXTRACTION'
LEFT JOIN
  platform_ext_latest
    ON CAST(platform_doc.id_platform_internal AS STRING) = platform_ext_latest.id_document
LEFT JOIN
  legacy_latest
    ON doc_base.id_external = legacy_latest.id_external
    AND doc_base.external_source = legacy_latest.legacy_external_source
