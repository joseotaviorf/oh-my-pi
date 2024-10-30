WITH extract_json_data AS (
  SELECT
    id_external,
    external_source,
    processing_result,
    documents_type,
    FROM_JSON(errors, "Array<Struct<type: STRING>>") AS extract_errors,
    FROM_JSON(
      GET_JSON_OBJECT(extracted_data, '$.documents'),
      "Array<
      Struct<
      metadata_analysis:struct<is_suspicious:BOOLEAN>
      >>"
    ) AS metadata_is_suspicious,
    FROM_JSON(
      GET_JSON_OBJECT(extracted_data, '$.documents'),
      "Array<
      Struct<
      metadata_analysis:struct<dates_divergent:BOOLEAN>
      >>"
    ) AS metadata_dates_divergent,
    FROM_JSON(
      GET_JSON_OBJECT(extracted_data, '$.documents'),
      "Array<
      Struct<
      data:struct<statement_type:STRING>
      >>"
    ) AS bank_statement_type,
    GET_JSON_OBJECT(extracted_data, '$.extracted_income') AS extracted_income,
    FROM_JSON(GET_JSON_OBJECT(extracted_data, '$.documents'), 'ARRAY<STRING>') AS documents,
    ts_created,
    ts_updated,
    NOW() AS ts_load
  FROM
    datalake_docpilot_clean.income_extraction
),
transform_income_data AS (
SELECT
    id_external,
    external_source,
    processing_result,
    documents_type,
    ARRAY_SIZE(extract_errors) AS number_of_documents_with_errors,
    ARRAY_SIZE(documents) AS number_of_processed_documents,
  REPLACE(
    REPLACE((CAST(extract_errors AS string)), '{{', ''),
    '}}',
    ''
  ) AS error_type,
  REPLACE(
    REPLACE((CAST(bank_statement_type AS string)), '{{', ''),
    '}}',
    ''
  ) AS bank_statement_type,
  IF(CAST(metadata_is_suspicious AS string) LIKE '%true%', TRUE, FALSE) AS any_suspicious_document,
  IF(CAST(metadata_dates_divergent AS string) LIKE '%true%', TRUE, FALSE) AS any_divergent_date,
  TRANSFORM(map_values(from_json(extracted_income, 'MAP<STRING, DECIMAL>')), x -> X::BIGINT) AS extracted_incomes,
  ts_created,
  ts_updated,
  ts_load
FROM
  extract_json_data
),
explode_income AS (
  SELECT
    id_external,
    EXPLODE(from_json(extracted_income, 'MAP<STRING, DECIMAL>')) AS (date, income)
  FROM
    extract_json_data
),
calculate_avg_income AS (
  SELECT
    id_external,
    ROUND(AVG(income), 2) AS avg_extracted_income
  FROM
    explode_income
  GROUP BY id_external
)

SELECT
    id.id_external,
    id.external_source,
    id.processing_result,
    id.documents_type,
    id.number_of_processed_documents,
    id.number_of_documents_with_errors,
    id.error_type,
    id.bank_statement_type,
    id.extracted_incomes,
    avg.avg_extracted_income,
    id.any_suspicious_document,
    id.any_divergent_date,
    id.ts_created,
    id.ts_updated,
    id.ts_load
FROM
  transform_income_data AS id
LEFT JOIN
  calculate_avg_income AS avg
    ON id.id_external = avg.id_external
