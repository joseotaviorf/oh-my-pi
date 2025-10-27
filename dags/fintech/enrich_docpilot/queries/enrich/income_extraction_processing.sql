WITH extract_errors AS (
  SELECT
    *,
    LOWER(regexp_replace(llm_bank_name, '[^A-Za-z0-9\s]+', '')) AS llm_normalized_bank_name
  FROM (
    SELECT
      id_external,
      GET_JSON_OBJECT(TO_JSON(errors), "$.type") AS error_type,
      GET_JSON_OBJECT(TO_JSON(errors), "$.detail.document_path") AS file_path,
      GET_JSON_OBJECT(TO_JSON(errors), "$.detail.detected_layout") AS detected_layout,
      GET_JSON_OBJECT(TO_JSON(errors), "$.detail.reference_date") AS error_reference_date,
      GET_JSON_OBJECT(TO_JSON(errors), "$.detail.identification_result.bank_name") AS llm_bank_name,
      GET_JSON_OBJECT(TO_JSON(errors), "$.detail.identification_result.document_type") AS llm_document_type
    FROM (
      SELECT
        id_external,
        EXPLODE(
          FROM_JSON(
            GET_JSON_OBJECT(errors, "$"),
            "array<struct<
              type:string,
              detail:struct<
                document_path:string,
                detected_layout:string,
                reference_date:string,
                identification_result:struct<
                  bank_name:string,
                  document_type:string
                >
              >
            >>"
          )
        ) AS errors
      FROM datalake_docpilot_clean.income_extraction
    )
  )
),
processing_errors AS (
  SELECT
    id_external,
    MAX(processing_error) AS processing_errors
  FROM (
    SELECT
      id_external,
      CASE WHEN error_type IN ('INVALID_DATE_RANGE', 'LESS_THAN_RECOMMENDED_PERIOD')
        THEN error_type
        ELSE NULL
      END AS processing_error
    FROM extract_errors
  )
  GROUP BY id_external
),
extract_json_data AS (
  SELECT
    id_external,
    external_source,
    processing_result,
    documents_type,
    FROM_JSON(errors, "array<struct<type:string>>") AS extract_errors,
    FROM_JSON(GET_JSON_OBJECT(extracted_data, '$.documents'), 'array<string>') AS all_documents,
    GET_JSON_OBJECT(extracted_data, '$.reference_date') AS reference_date,
    GET_JSON_OBJECT(extracted_data, '$.extracted_income') AS processed_net_income,
    GET_JSON_OBJECT(extracted_data, '$.gross_income') AS processed_gross_income,
    GET_JSON_OBJECT(extracted_data, '$.committed_income') AS committed_income,
    FROM_JSON(
      GET_JSON_OBJECT(extracted_data, '$.documents'),
      'array<struct<
        data:struct<
          end_date:string,
          start_date:string,
          date:string,
          net_income:string,
          gross_income:string,
          statement_type:string,
          entries:array<struct<
            amount:string,
            category:string
          >>
        >,
        path:string,
        metadata_analysis:struct<
          is_suspicious:boolean,
          dates_divergent:boolean
        >
      >>'
    ) AS documents,
    ts_created,
    ts_updated
  FROM datalake_docpilot_clean.income_extraction
),
analysis_data AS (
  SELECT DISTINCT
    id_external,
    external_source,
    processing_result,
    documents_type,
    reference_date,
    processed_net_income,
    processed_gross_income,
    committed_income,
    ARRAY_SIZE(extract_errors) AS number_of_errors,
    ARRAY_SIZE(all_documents) AS number_of_processed_documents,
    ts_created,
    ts_updated
  FROM extract_json_data
),
explode_documents AS (
  SELECT
    id_external,
    document.path AS file_path,
    document.data.date AS document_date,
    document.data.end_date AS document_end_date,
    document.data.start_date AS document_start_date,
    document.data.statement_type AS statement_type,
    document.data.gross_income AS payslip_gross_income,
    document.data.net_income AS payslip_net_income,
    document.data.entries AS payslip_entries,
    document.metadata_analysis.is_suspicious AS is_suspicious,
    document.metadata_analysis.dates_divergent AS dates_divergent
  FROM extract_json_data
  LATERAL VIEW OUTER EXPLODE(documents) AS document
),
salary_advances AS (
  SELECT
    id_external,
    file_path,
    document_date,
    MAX(CASE WHEN entrie.category = 'salary_advance' THEN entrie.amount END) AS advance
  FROM explode_documents
  LATERAL VIEW OUTER EXPLODE(payslip_entries) AS entrie
  GROUP BY id_external, file_path, document_date
),
join_document_error AS (
  SELECT
    COALESCE(ed.id_external, er.id_external) AS id_external,
    COALESCE(ed.file_path, er.file_path) AS file_path,
    ed.payslip_gross_income,
    ed.payslip_net_income,
    ed.statement_type,
    ed.document_date,
    ed.document_end_date,
    ed.document_start_date,
    er.error_type,
    pe.processing_errors,
    er.file_path AS error_file_path,
    er.detected_layout,
    er.llm_bank_name,
    er.llm_document_type,
    er.llm_normalized_bank_name,
    ed.is_suspicious,
    ed.dates_divergent
  FROM explode_documents ed
  FULL OUTER JOIN extract_errors er
    ON ed.id_external = er.id_external AND ed.file_path = er.file_path
  LEFT JOIN processing_errors pe
    ON ed.id_external = pe.id_external
),
join_all_data AS (
  SELECT
    ad.id_external,
    jd.file_path,
    ad.external_source,
    ad.processing_result,
    ad.documents_type,
    jd.statement_type,
    ad.reference_date,
    ad.processed_net_income,
    ad.processed_gross_income,
    jd.payslip_net_income,
    jd.payslip_gross_income,
    sa.advance,
    ad.committed_income,
    ad.number_of_errors,
    ad.number_of_processed_documents,
    jd.document_date,
    jd.document_end_date,
    jd.document_start_date,
    jd.error_type,
    jd.processing_errors,
    jd.error_file_path,
    jd.detected_layout,
    jd.llm_bank_name,
    jd.llm_document_type,
    jd.llm_normalized_bank_name,
    jd.is_suspicious,
    jd.dates_divergent,
    ad.ts_created,
    ad.ts_updated
  FROM analysis_data ad
  LEFT JOIN join_document_error jd
    ON ad.id_external = jd.id_external
  LEFT JOIN salary_advances sa
    ON sa.id_external = jd.id_external
    AND sa.file_path = jd.file_path
    AND sa.document_date = jd.document_date
  WHERE jd.file_path IS NOT NULL
),
explode_net_income AS (
  SELECT
    id_external,
    EXPLODE(FROM_JSON(processed_net_income, 'map<string,decimal>')) AS (date, net_income)
  FROM join_all_data
),
explode_gross_income AS (
  SELECT
    id_external,
    EXPLODE(FROM_JSON(processed_gross_income, 'map<string,decimal>')) AS (date, gross_income)
  FROM join_all_data
),
explode_committed_income AS (
  SELECT
    id_external,
    EXPLODE(FROM_JSON(committed_income, 'map<string,decimal>')) AS (date, committed_income)
  FROM join_all_data
),
get_incomes AS (
  SELECT
    n.id_external,
    n.date,
    ROUND(n.net_income, 2) AS net_income,
    ROUND(g.gross_income, 2) AS gross_income,
    ROUND(c.committed_income, 2) AS committed_income
  FROM explode_net_income n
  LEFT JOIN explode_gross_income g
    ON n.id_external = g.id_external AND n.date = g.date
  LEFT JOIN explode_committed_income c
    ON c.id_external = n.id_external AND c.date = n.date
),
avg_incomes AS (
  SELECT
    id_external,
    ROUND(AVG(net_income), 2) AS avg_net_income,
    ROUND(AVG(gross_income), 2) AS avg_gross_income,
    ROUND(AVG(committed_income), 2) AS avg_committed_income
  FROM get_incomes
  GROUP BY id_external
),
median_incomes AS (
  SELECT
    id_external,
    ROUND(median(net_income), 2) AS median_net_income,
    ROUND(median(gross_income), 2) AS median_gross_income,
    ROUND(median(committed_income), 2) AS median_committed_income
  FROM get_incomes
  GROUP BY id_external
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
    jd.file_path,
    uf.cpf,
    jd.external_source,
    jd.processing_result,
    jd.documents_type,
    jd.statement_type,
    jd.number_of_errors,
    jd.number_of_processed_documents,
    jd.error_type,
    jd.processing_errors,
    jd.error_file_path,
    jd.detected_layout,
    jd.llm_bank_name,
    jd.llm_document_type,
    jd.llm_normalized_bank_name,
    gi.date AS reference_period,
    COALESCE(jd.payslip_net_income, gi.net_income) AS net_income,
    COALESCE(jd.payslip_gross_income, gi.gross_income) AS gross_income,
    gi.net_income AS processed_net_income,
    gi.gross_income AS processed_gross_income,
    jd.advance,
    gi.committed_income,
    av.avg_net_income,
    av.avg_gross_income,
    av.avg_committed_income,
    mi.median_net_income,
    mi.median_gross_income,
    mi.median_committed_income,
    jd.is_suspicious,
    jd.dates_divergent AS is_dates_divergent,
    jd.reference_date,
    jd.document_date,
    jd.document_end_date,
    jd.document_start_date,
    jd.ts_created,
    jd.ts_updated,
    NOW() AS ts_load
  FROM join_all_data jd
  LEFT JOIN datalake_docx_clean.document d
    ON jd.id_external = d.id
  LEFT JOIN user_folder uf
    ON d.id_folder = uf.id_folder
    AND CAST(d.id_context_external AS bigint) = uf.id_proposal
  LEFT JOIN get_incomes gi
    ON gi.id_external = jd.id_external
    AND (
      (gi.date >= jd.document_start_date AND gi.date < jd.document_end_date)
      OR gi.date = jd.document_date
    )
    AND jd.error_type IS NULL
  LEFT JOIN avg_incomes av
    ON av.id_external = jd.id_external
  LEFT JOIN median_incomes mi
    ON mi.id_external = jd.id_external
),
get_user AS (
  SELECT
    id AS id_user,
    cpf
  FROM datalake_ebdb_user.user
  QUALIFY ROW_NUMBER() OVER (PARTITION BY cpf ORDER BY ts_created DESC) = 1
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
  id.statement_type,
  id.llm_normalized_bank_name,
  id.number_of_processed_documents,
  id.number_of_errors,
  id.error_type,
  id.processing_errors,
  id.error_file_path,
  id.detected_layout,
  id.llm_bank_name,
  id.llm_document_type,
  TO_DATE(id.reference_date) AS reference_date,
  TO_DATE(id.reference_period) AS reference_period,
  id.net_income,
  id.gross_income,
  id.processed_net_income,
  id.processed_gross_income,
  id.committed_income,
  id.advance,
  id.avg_net_income,
  id.avg_gross_income,
  id.avg_committed_income,
  id.median_net_income,
  id.median_gross_income,
  id.median_committed_income,
  IF(u.id_user IS NOT NULL, TRUE, FALSE) AS is_main_user,
  id.is_suspicious,
  id.is_dates_divergent,
  DATE(id.document_date) AS dt_document_date,
  DATE(id.document_end_date) AS dt_document_end_date,
  DATE(id.document_start_date) AS dt_document_start_date,
  id.ts_created,
  id.ts_updated,
  id.ts_load
FROM transform_income_data id
LEFT JOIN get_user u
  ON u.cpf = id.cpf
