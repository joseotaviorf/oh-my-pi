WITH extract_errors AS (
  SELECT
    id_external,
    get_json_object(to_json(errors), "$.type") as error_type,
    get_json_object(to_json(errors), "$.detail.document_path") as file_path,
    get_json_object(to_json(errors), "$.detail.detected_layout") as detected_layout
  FROM (
    SELECT
      id_external,
      explode(from_json(
        get_json_object(errors, "$"),
        "Array<
          Struct<
            type:string,
            detail: Struct<
              document_path:string,
              detected_layout:string
            >
          >
        >")) as errors
    FROM datalake_docpilot_clean.income_extraction
  )
),
extract_json_data AS (
  SELECT
    id_external,
    external_source,
    processing_result,
    documents_type,
    FROM_JSON(errors, "Array<Struct<type: STRING>>") AS extract_errors,
    FROM_JSON(
      GET_JSON_OBJECT(extracted_data, '$.documents'),
      'ARRAY<STRING>'
    ) AS all_documents,
    GET_JSON_OBJECT(extracted_data, '$.reference_date') AS reference_date,
    GET_JSON_OBJECT(extracted_data, '$.extracted_income') AS net_income,
    GET_JSON_OBJECT(extracted_data, '$.gross_income') AS gross_income,
    GET_JSON_OBJECT(extracted_data, '$.committed_income') AS committed_income,
    FROM_JSON(
      GET_JSON_OBJECT(extracted_data, '$.documents'),
      'ARRAY<STRUCT<data:STRUCT<end_date:STRING, start_date:STRING, date:STRING>, path:STRING, metadata_analysis:STRUCT<is_suspicious:BOOLEAN, dates_divergent:BOOLEAN>>>'
    ) AS documents,
    ts_created,
    ts_updated
  FROM
    datalake_docpilot_clean.income_extraction
),
explode_documents AS (
  SELECT
    id_external,
    document.path AS file_path,
    external_source,
    processing_result,
    documents_type,
    reference_date,
    net_income,
    gross_income,
    committed_income,
    ARRAY_SIZE(extract_errors) AS number_of_errors,
    ARRAY_SIZE(all_documents) AS number_of_processed_documents,
    document.data.date AS document_date,
    document.data.end_date AS document_end_date,
    document.data.start_date AS document_start_date,
    document.metadata_analysis.is_suspicious AS is_suspicious,
    document.metadata_analysis.dates_divergent AS dates_divergent,
    ts_created,
    ts_updated
  FROM
    extract_json_data
    LATERAL VIEW OUTER EXPLODE(documents) AS document
),
join_document_erros AS (
  SELECT
    ed.id_external,
    ed.file_path,
    ed.external_source,
    ed.processing_result,
    ed.documents_type,
    ed.reference_date,
    ed.net_income,
    ed.gross_income,
    ed.committed_income,
    ed.number_of_errors,
    ed.number_of_processed_documents,
    ed.document_date,
    ed.document_end_date,
    ed.document_start_date,
    er.error_type,
    er.file_path AS error_file_path,
    er.detected_layout,
    ed.is_suspicious,
    ed.dates_divergent,
    ed.ts_created,
    ed.ts_updated
  FROM explode_documents AS ed
  LEFT JOIN
    extract_errors AS er
    ON (
    ed.id_external = er.id_external
    AND (ed.file_path = er.file_path OR
    er.file_path IS NULL OR ed.file_path IS NULL
    )
    )
),
explode_net_income AS (
  SELECT
    id_external,
    EXPLODE(from_json(net_income, 'MAP<STRING, DECIMAL>')) AS (date, net_income)
  FROM
    join_document_erros
),
explode_gross_income AS (
  SELECT
    id_external,
    EXPLODE(from_json(gross_income, 'MAP<STRING, DECIMAL>')) AS (date, gross_income)
  FROM
    join_document_erros
),
explode_committed_income AS (
  SELECT
    id_external,
    EXPLODE(
      from_json(committed_income, 'MAP<STRING, DECIMAL>')
    ) AS (date, committed_income)
  FROM
    join_document_erros
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
    jd.file_path,
    uf.cpf,
    jd.external_source,
    jd.processing_result,
    jd.documents_type,
    jd.number_of_errors AS number_of_documents_with_errors,
    jd.number_of_processed_documents,
    jd.error_type,
    jd.error_file_path,
    jd.detected_layout,
    gi.date AS reference_period,
    gi.net_income,
    gi.gross_income,
    gi.committed_income,
    av.avg_net_income AS avg_net_income,
    av.avg_gross_income AS avg_gross_income,
    av.avg_committed_income AS avg_committed_income,
    jd.is_suspicious,
    jd.dates_divergent AS is_dates_divergent,
    jd.reference_date,
    jd.document_date,
    jd.document_end_date,
    jd.document_start_date,
    jd.ts_created,
    jd.ts_updated,
    NOW() AS ts_load
  FROM
    join_document_erros AS jd
    LEFT JOIN datalake_docx_clean.document AS d ON jd.id_external = d.id
    LEFT JOIN user_folder AS uf ON (
      d.id_folder = uf.id_folder
      AND CAST(d.id_context_external AS bigint) = uf.id_proposal
    )
    LEFT JOIN get_incomes AS gi
      ON gi.id_external = jd.id_external
      AND (gi.date = jd.document_start_date OR gi.date = jd.document_date)
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
SELECT DISTINCT
    id.id_document,
    id.id_proposal,
    u.id_user,
    id.file_path,
    REPLACE(REPLACE(id.cpf, ".", ""), "-", "") AS cpf,
    id.external_source,
    id.processing_result,
    id.documents_type,
    id.number_of_processed_documents,
    id.number_of_documents_with_errors,
    id.error_type,
    id.error_file_path,
    id.detected_layout,
    TO_DATE(id.reference_date) AS reference_date,
    TO_DATE(id.reference_period) AS reference_period,
    id.net_income,
    id.gross_income,
    id.committed_income,
    id.avg_net_income,
    id.avg_gross_income,
    id.avg_committed_income,
    IF(u.id_user IS NOT NULL, TRUE, FALSE) AS is_main_user,
    id.is_suspicious,
    id.is_dates_divergent,
    DATE(id.document_date) AS dt_document_date,
    DATE(id.document_end_date) AS dt_document_end_date,
    DATE(id.document_start_date) AS dt_document_start_date,
    id.ts_created,
    id.ts_updated,
    id.ts_load
FROM
  transform_income_data AS id
LEFT JOIN get_user AS u
    ON u.cpf = id.cpf
