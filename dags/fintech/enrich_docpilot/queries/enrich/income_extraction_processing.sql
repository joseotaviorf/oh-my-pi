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
user_folder AS (
SELECT DISTINCT
  id_folder,
  id_context_external AS id_proposal,
  cpf
FROM datalake_docx.personal_documentation
),
transform_income_data AS (
SELECT
    CAST(jd.id_external AS bigint) AS id_document,
    CAST(d.id_context_external AS bigint) AS id_proposal,
    uf.cpf,
    jd.external_source,
    jd.processing_result,
    jd.documents_type,
    ARRAY_SIZE(jd.extract_errors) AS number_of_documents_with_errors,
    ARRAY_SIZE(jd.documents) AS number_of_processed_documents,
  REPLACE(
    REPLACE((CAST(jd.extract_errors AS string)), '{{', ''),
    '}}',
    ''
  ) AS error_type,
  REPLACE(
    REPLACE((CAST(jd.bank_statement_type AS string)), '{{', ''),
    '}}',
    ''
  ) AS bank_statement_type,
  IF(CAST(jd.metadata_is_suspicious AS string) LIKE '%true%', TRUE, FALSE) AS any_suspicious_document,
  IF(CAST(jd.metadata_dates_divergent AS string) LIKE '%true%', TRUE, FALSE) AS any_divergent_date,
  TRANSFORM(map_values(from_json(jd.extracted_income, 'MAP<STRING, DECIMAL>')), x -> X::BIGINT) AS extracted_incomes,
  jd.ts_created,
  jd.ts_updated,
  jd.ts_load
FROM
  extract_json_data AS jd
LEFT JOIN
  datalake_docx_clean.document AS d
    ON jd.id_external = d.id
LEFT JOIN
  user_folder AS uf
    ON (d.id_folder = uf.id_folder AND CAST(d.id_context_external AS bigint) = uf.id_proposal)
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY d.id_context_external, uf.cpf ORDER BY jd.ts_created DESC) = 1
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
),
get_user AS (
  SELECT
    id AS id_user,
    cpf
  FROM
  datalake_ebdb_user.user
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY cpf ORDER BY ts_created DESC) = 1
)

SELECT
    id.id_document,
    id.id_proposal,
    u.id_user,
    id.cpf,
    id.external_source,
    id.processing_result,
    id.documents_type,
    id.number_of_processed_documents,
    id.number_of_documents_with_errors,
    id.error_type,
    id.bank_statement_type,
    id.extracted_incomes,
    avg.avg_extracted_income,
    IF(u.id_user IS NOT NULL, TRUE, FALSE) AS is_main_user,
    id.any_suspicious_document,
    id.any_divergent_date,
    id.ts_created,
    id.ts_updated,
    id.ts_load
FROM
  transform_income_data AS id
LEFT JOIN
  calculate_avg_income AS avg
    ON id.id_document = avg.id_external
LEFT JOIN get_user AS u
    ON u.cpf = id.cpf
