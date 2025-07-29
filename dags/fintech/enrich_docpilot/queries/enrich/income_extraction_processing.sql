WITH extract_errors AS (
  SELECT
  *,
  LOWER(regexp_replace(llm_bank_name, '[^A-Za-z0-9\s]+', '')) AS llm_normalized_bank_name
FROM (
  SELECT
    id_external,
    get_json_object(to_json(errors), "$.type") as error_type,
    get_json_object(to_json(errors), "$.detail.document_path") as file_path,
    get_json_object(to_json(errors), "$.detail.detected_layout") AS detected_layout,
    get_json_object(to_json(errors), "$.detail.reference_date") AS error_reference_date,
    get_json_object(to_json(errors), "$.detail.identification_result.bank_name") AS llm_bank_name,
    get_json_object(to_json(errors), "$.detail.identification_result.document_type") AS llm_document_type
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
              detected_layout:string,
              reference_date:string,
              identification_result: Struct<
                bank_name:string,
                document_type:string
              >
            >
          >
        >"
        )) as errors
    FROM datalake_docpilot_clean.income_extraction
    )
  )
),
processing_errors AS (
    SELECT
    id_external,
    MAX(processing_error) as processing_errors
    FROM(
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
      'ARRAY<STRUCT<data:STRUCT<end_date:STRING, start_date:STRING, date:STRING, statement_type:String>, path:STRING, metadata_analysis:STRUCT<is_suspicious:BOOLEAN, dates_divergent:BOOLEAN>>>'
    ) AS documents,
    ts_created,
    ts_updated
  FROM
    datalake_docpilot_clean.income_extraction
),
analysis_data AS(
  SELECT
  DISTINCT
    id_external,
    external_source,
    processing_result,
    documents_type,
    reference_date,
    net_income,
    gross_income,
    committed_income,
    ARRAY_SIZE(extract_errors) AS number_of_errors,
    ARRAY_SIZE(all_documents) AS number_of_processed_documents,
    ts_created,
    ts_updated
    FROM
    extract_json_data
),
explode_documents AS (
   SELECT
    id_external,
    document.path AS file_path,
    document.data.date AS document_date,
    document.data.end_date AS document_end_date,
    document.data.start_date AS document_start_date,
    document.data.statement_type as statement_type,
    document.metadata_analysis.is_suspicious AS is_suspicious,
    document.metadata_analysis.dates_divergent AS dates_divergent
  FROM
    extract_json_data
    LATERAL VIEW OUTER EXPLODE(documents) AS document
), join_document_error AS(
  SELECT
    COALESCE(ed.id_external, er.id_external) as id_external,
    COALESCE(ed.file_path, er.file_path) AS file_path,
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
  FROM explode_documents AS ed
  FULL OUTER JOIN
    extract_errors AS er
    ON
    ed.id_external = er.id_external
    AND
    ed.file_path = er.file_path
    LEFT JOIN processing_errors pe
    ON ed.id_external = pe.id_external
), join_all_data(
SELECT
    ad.id_external,
    jd.file_path,
    ad.external_source,
    ad.processing_result,
    ad.documents_type,
    jd.statement_type,
    ad.reference_date,
    ad.net_income,
    ad.gross_income,
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
  WHERE file_path IS NOT NULL
),
explode_net_income AS (
  SELECT
    id_external,
    EXPLODE(from_json(net_income, 'MAP<STRING, DECIMAL>')) AS (date, net_income)
  FROM
    join_all_data
),
explode_gross_income AS (
  SELECT
    id_external,
    EXPLODE(from_json(gross_income, 'MAP<STRING, DECIMAL>')) AS (date, gross_income)
  FROM
    join_all_data
),
explode_committed_income AS (
  SELECT
    id_external,
    EXPLODE(
      from_json(committed_income, 'MAP<STRING, DECIMAL>')
    ) AS (date, committed_income)
  FROM
    join_all_data
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
median_incomes AS (
  SELECT
    id_external,
    ROUND(MEDIAN(net_income), 2) AS median_net_income,
    ROUND(MEDIAN(gross_income), 2) AS median_gross_income,
    ROUND(MEDIAN(committed_income), 2) AS median_committed_income
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
    gi.net_income,
    gi.gross_income,
    gi.committed_income,
    av.avg_net_income AS avg_net_income,
    av.avg_gross_income AS avg_gross_income,
    av.avg_committed_income AS avg_committed_income,
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
  FROM
    join_all_data AS jd
    LEFT JOIN datalake_docx_clean.document AS d ON jd.id_external = d.id
    LEFT JOIN user_folder AS uf ON (
      d.id_folder = uf.id_folder
      AND CAST(d.id_context_external AS bigint) = uf.id_proposal
    )
    LEFT JOIN get_incomes AS gi
      ON gi.id_external = jd.id_external
      AND (
        (gi.date >= jd.document_start_date
        AND gi.date < jd.document_end_date)
        OR
        gi.date = jd.document_date )
        AND jd.error_type IS NULL
    LEFT JOIN avg_incomes AS av
      ON av.id_external = jd.id_external
    LEFT JOIN median_incomes AS mi
      ON mi.id_external = jd.id_external
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
    id.committed_income,
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
FROM
  transform_income_data AS id
LEFT JOIN get_user AS u
    ON u.cpf = id.cpf
