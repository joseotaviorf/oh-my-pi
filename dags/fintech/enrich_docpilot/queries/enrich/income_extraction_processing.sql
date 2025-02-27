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
    GET_JSON_OBJECT(extracted_data, '$.reference_date') AS reference_date,
    GET_JSON_OBJECT(extracted_data, '$.extracted_income') AS net_income,
    GET_JSON_OBJECT(extracted_data, '$.gross_income') AS gross_income,
    GET_JSON_OBJECT(extracted_data, '$.committed_income') AS committed_income,
    FROM_JSON(
      GET_JSON_OBJECT(extracted_data, '$.documents'),
      'ARRAY<STRING>'
    ) AS documents,
    ts_created,
    ts_updated,
    NOW() AS ts_load
  FROM
    datalake_docpilot_clean.income_extraction
),
explode_net_income AS (
  SELECT
    id_external,
    EXPLODE(from_json(net_income, 'MAP<STRING, DECIMAL>')) AS (date, net_income)
  FROM
    extract_json_data
),
explode_gross_income AS (
  SELECT
    id_external,
    EXPLODE(from_json(gross_income, 'MAP<STRING, DECIMAL>')) AS (date, gross_income)
  FROM
    extract_json_data
),
explode_committed_income AS (
  SELECT
    id_external,
    EXPLODE(
      from_json(committed_income, 'MAP<STRING, DECIMAL>')
    ) AS (date, committed_income)
  FROM
    extract_json_data
),
get_incomes AS (
  SELECT
    n.id_external,
    n.date,
    ROUND(n.net_income, 2) AS net_income,
    ROUND(g.gross_income, 2) AS gross_income,
    ROUND(c.committed_income, 2) AS committed_income
  FROM
    explode_net_income AS n
    LEFT JOIN explode_gross_income AS g
      ON n.id_external = g.id_external
        AND n.date = g.date
    LEFT JOIN explode_committed_income AS c
      ON c.id_external = n.id_external
        AND c.date = n.date
),
avg_incomes AS (
  SELECT
    id_external,
    ROUND(AVG(net_income), 2) AS avg_net_income,
    ROUND(AVG(gross_income), 2) AS avg_gross_income,
    ROUND(AVG(committed_income), 2) AS avg_committed_income
  FROM
    get_incomes
  GROUP BY id_external
),
user_folder AS (
  SELECT
    DISTINCT id_folder,
    id_context_external AS id_proposal,
    cpf
  FROM
    datalake_docx.personal_documentation
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
      REPLACE(
        (CAST(jd.bank_statement_type AS string)),
        '{{',
        ''
      ),
      '}}',
      ''
    ) AS bank_statement_type,
    gi.date AS reference_period,
    gi.net_income,
    gi.gross_income,
    gi.committed_income,
    av.avg_net_income AS avg_net_income,
    av.avg_gross_income AS avg_gross_income,
    av.avg_committed_income AS avg_committed_income,
    IF(
      CAST(jd.metadata_is_suspicious AS string) LIKE '%true%',
      TRUE,
      FALSE
    ) AS any_suspicious_document,
    IF(
      CAST(jd.metadata_dates_divergent AS string) LIKE '%true%',
      TRUE,
      FALSE
    ) AS any_divergent_date,
    jd.reference_date,
    jd.ts_created,
    jd.ts_updated,
    jd.ts_load
  FROM
    extract_json_data AS jd
    LEFT JOIN datalake_docx_clean.document AS d ON jd.id_external = d.id
    LEFT JOIN user_folder AS uf ON (
      d.id_folder = uf.id_folder
      AND CAST(d.id_context_external AS bigint) = uf.id_proposal
    )
    LEFT JOIN get_incomes AS gi
      ON gi.id_external = jd.id_external
    LEFT JOIN avg_incomes AS av
      ON av.id_external = jd.id_external
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
    REPLACE(REPLACE(id.cpf, ".", ""), "-", "") AS cpf,
    id.external_source,
    id.processing_result,
    id.documents_type,
    id.number_of_processed_documents,
    id.number_of_documents_with_errors,
    id.error_type,
    id.bank_statement_type,
    TO_DATE(id.reference_date) AS reference_date,
    TO_DATE(id.reference_period) AS reference_period,
    id.net_income,
    id.gross_income,
    id.committed_income,
    id.avg_net_income,
    id.avg_gross_income,
    id.avg_committed_income,
    ROW_NUMBER() OVER (PARTITION BY id.id_document ORDER BY TO_DATE(id.reference_period) DESC) AS document_number,
    IF(u.id_user IS NOT NULL, TRUE, FALSE) AS is_main_user,
    id.any_suspicious_document,
    id.any_divergent_date,
    id.ts_created,
    id.ts_updated,
    id.ts_load
FROM
  transform_income_data AS id
LEFT JOIN get_user AS u
    ON u.cpf = id.cpf
