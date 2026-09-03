WITH batch_base AS (
  SELECT
    batch.id AS id_batch,
    CAST(batch.id_external AS BIGINT) AS id_external,
    batch.external_source,
    batch.status AS apurador_status,
    batch.error_type AS apurador_error_type,
    batch.error AS apurador_error,
    batch.output_schema_version AS apurador_output_schema_version,
    batch.ts_created AS ts_batch_created,
    GET_JSON_OBJECT(batch.business_output, '$.reference_date') AS dt_apurador_reference,
    GET_JSON_OBJECT(batch.business_output, '$.analysis') AS apurador_analysis,
    GET_JSON_OBJECT(batch.business_output, '$.extracted_income') AS apurador_extracted_income_json,
    GET_JSON_OBJECT(batch.business_output, '$.gross_income') AS apurador_gross_income_json,
    GET_JSON_OBJECT(batch.business_output, '$.committed_income') AS apurador_committed_income_json,
    GET_JSON_OBJECT(batch.pipeline_metadata, '$.commit_hash') AS apurador_commit_hash,
    GET_JSON_OBJECT(batch.pipeline_metadata, '$.handler_type') AS apurador_handler_type,
    GET_JSON_OBJECT(batch.pipeline_metadata, '$.diagnostics.n_periods') AS apurador_n_periods,
    GET_JSON_OBJECT(
      batch.pipeline_metadata,
      '$.diagnostics.median_extracted_income'
    ) AS apurador_median_extracted_income,
    GET_JSON_OBJECT(batch.pipeline_metadata, '$.handlers[0].handler') AS apurador_handler_name,
    GET_JSON_OBJECT(batch.pipeline_metadata, '$.handlers[0].prompt') AS apurador_handler_prompt,
    GET_JSON_OBJECT(batch.pipeline_metadata, '$.handlers[0].version') AS apurador_handler_version,
    CASE
      WHEN batch.business_output IS NOT NULL
        AND GET_JSON_OBJECT(batch.business_output, '$.extracted_income') IS NOT NULL
      THEN TRUE
      ELSE FALSE
    END AS has_apurador_income_map
  FROM
    datalake_docpilot_clean.income_extraction_batch AS batch
),
legacy_latest AS (
  SELECT
    id_external,
    legacy_external_source,
    legacy_processing_result,
    legacy_documents_type,
    dt_legacy_reference,
    legacy_extracted_income_json,
    legacy_gross_income_json,
    legacy_committed_income_json,
    legacy_first_error_type,
    legacy_error_count,
    ts_legacy_created,
    ts_legacy_updated
  FROM (
    SELECT
      CAST(id_external AS BIGINT) AS id_external,
      external_source AS legacy_external_source,
      processing_result AS legacy_processing_result,
      documents_type AS legacy_documents_type,
      GET_JSON_OBJECT(extracted_data, '$.reference_date') AS dt_legacy_reference,
      GET_JSON_OBJECT(extracted_data, '$.extracted_income') AS legacy_extracted_income_json,
      GET_JSON_OBJECT(extracted_data, '$.gross_income') AS legacy_gross_income_json,
      GET_JSON_OBJECT(extracted_data, '$.committed_income') AS legacy_committed_income_json,
      GET_JSON_OBJECT(errors, '$[0].type') AS legacy_first_error_type,
      SIZE(FROM_JSON(errors, 'array<struct<type:string>>')) AS legacy_error_count,
      ts_created AS ts_legacy_created,
      ts_updated AS ts_legacy_updated,
      ROW_NUMBER() OVER (
        PARTITION BY id_external, external_source
        ORDER BY ts_updated DESC, ts_created DESC
      ) AS rn
    FROM
      datalake_docpilot_clean.income_extraction
  ) AS ranked_legacy_extractions
  WHERE
    rn = 1
),
batch_with_legacy AS (
  SELECT
    batch_base.id_batch,
    batch_base.id_external,
    batch_base.external_source,
    batch_base.apurador_status,
    batch_base.apurador_error_type,
    batch_base.apurador_error,
    batch_base.apurador_output_schema_version,
    batch_base.apurador_analysis,
    batch_base.apurador_extracted_income_json,
    batch_base.apurador_gross_income_json,
    batch_base.apurador_committed_income_json,
    batch_base.apurador_commit_hash,
    batch_base.apurador_handler_type,
    batch_base.apurador_handler_name,
    batch_base.apurador_handler_prompt,
    batch_base.apurador_handler_version,
    batch_base.apurador_n_periods,
    batch_base.apurador_median_extracted_income,
    batch_base.has_apurador_income_map,
    batch_base.dt_apurador_reference,
    batch_base.ts_batch_created,
    legacy_latest.legacy_processing_result,
    legacy_latest.legacy_documents_type,
    legacy_latest.dt_legacy_reference,
    legacy_latest.legacy_extracted_income_json,
    legacy_latest.legacy_gross_income_json,
    legacy_latest.legacy_committed_income_json,
    legacy_latest.legacy_first_error_type,
    legacy_latest.legacy_error_count,
    legacy_latest.ts_legacy_created,
    legacy_latest.ts_legacy_updated,
    legacy_latest.legacy_processing_result IS NOT NULL AS has_legacy_record,
    ROW_NUMBER() OVER (
      PARTITION BY batch_base.id_external, batch_base.external_source
      ORDER BY batch_base.ts_batch_created DESC
    ) AS rn
  FROM
    batch_base
  LEFT JOIN
    legacy_latest
      ON batch_base.id_external = legacy_latest.id_external
      AND batch_base.external_source = legacy_latest.legacy_external_source
)
SELECT
  id_batch,
  id_external,
  external_source,
  apurador_status,
  apurador_error_type,
  apurador_error,
  apurador_output_schema_version,
  apurador_analysis,
  apurador_extracted_income_json,
  apurador_gross_income_json,
  apurador_committed_income_json,
  apurador_commit_hash,
  apurador_handler_type,
  apurador_handler_name,
  apurador_handler_prompt,
  apurador_handler_version,
  legacy_processing_result,
  legacy_documents_type,
  legacy_extracted_income_json,
  legacy_gross_income_json,
  legacy_committed_income_json,
  legacy_first_error_type,
  apurador_n_periods,
  apurador_median_extracted_income,
  legacy_error_count,
  has_apurador_income_map,
  has_legacy_record,
  rn = 1 AS is_latest_batch_for_external,
  dt_apurador_reference,
  dt_legacy_reference,
  ts_batch_created,
  ts_legacy_created,
  ts_legacy_updated,
  NOW() AS ts_load
FROM
  batch_with_legacy
