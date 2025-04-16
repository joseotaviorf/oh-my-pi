WITH get_docpilot_annotations AS (
  SELECT
    project.id AS id_project,
    task.id_proposal,
    task.id AS id_task,
    task.total_annotations,
    task_completion.lead_time,
    task_completion.id_completed_by,
    task.proponent_cpf,
    task.proponent_name,
    task_completion.result,
    EXPLODE(
      FROM_JSON(
        GET_JSON_OBJECT(task_completion.result, "$"),
        "ARRAY<
          STRUCT<
            from_name: STRING,
            type: STRING,
            value: STRUCT<
              choices: ARRAY<STRING>,
              text: ARRAY<STRING>
            >
          >
        >"
      )
    ) AS input_answer,
    FROM_JSON(
      task.data,
      'STRUCT<
      document_1: STRING,
      document_2: STRING,
      document_3: STRING,
      document_4: STRING,
      document_5: STRING,
      document_6: STRING,
      document_7: STRING,
      document_8: STRING,
      document_9: STRING,
      document_10: STRING
    >'
    ) AS extracted_data,
    task_completion.ts_updated
  FROM
    datalake_quinturk_clean.project
      INNER JOIN datalake_quinturk_clean.task
        ON project.id = task.id_project
      INNER JOIN datalake_quinturk_clean.task_completion
        ON task_completion.id_task = task.id
  WHERE
    title LIKE "%[DocPilot] Auditoria%"
),
extract_input_value AS (
  SELECT
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    total_annotations,
    lead_time,
    extracted_data.document_1 AS document_1_path,
    extracted_data.document_2 AS document_2_path,
    extracted_data.document_3 AS document_3_path,
    extracted_data.document_4 AS document_4_path,
    extracted_data.document_5 AS document_5_path,
    extracted_data.document_6 AS document_6_path,
    extracted_data.document_7 AS document_7_path,
    extracted_data.document_8 AS document_8_path,
    extracted_data.document_9 AS document_9_path,
    extracted_data.document_10 AS document_10_path,
    REGEXP_REPLACE(
      GET_JSON_OBJECT(TO_JSON(input_answer), "$.from_name"), '[A-Za-z_]+$', ""
    ) AS document_name,
    REGEXP_REPLACE(
      GET_JSON_OBJECT(TO_JSON(input_answer), "$.from_name"), '^document_[0-9]+_', ""
    ) AS field_type,
    REPLACE(
      COALESCE(
        GET_JSON_OBJECT(TO_JSON(input_answer), "$.value.choices[0]"),
        GET_JSON_OBJECT(TO_JSON(input_answer), "$.value.text[0]")
      ),
      ' ',
      ''
    ) AS input_value,
    ts_updated
  FROM
    get_docpilot_annotations
),
get_input_value AS (
  SELECT
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    total_annotations,
    lead_time,
    document_name,
    CASE
      WHEN document_name = 'document_1' THEN document_1_path
      WHEN document_name = 'document_2' THEN document_2_path
      WHEN document_name = 'document_3' THEN document_3_path
      WHEN document_name = 'document_4' THEN document_4_path
      WHEN document_name = 'document_5' THEN document_5_path
      WHEN document_name = 'document_6' THEN document_6_path
      WHEN document_name = 'document_7' THEN document_7_path
      WHEN document_name = 'document_8' THEN document_8_path
      WHEN document_name = 'document_9' THEN document_9_path
      WHEN document_name = 'document_10' THEN document_10_path
    END AS document_path,
    CASE
      WHEN
        field_type = 'type'
        AND input_value = 'BANK_STATEMENT'
      THEN
        'BANK_STATEMENT'
      WHEN
        field_type = 'type'
        AND input_value = 'PAYSLIP'
      THEN
        'PAYSLIP'
      WHEN
        field_type = 'type'
        AND input_value = 'INSS'
      THEN
        'INSS'
      WHEN
        field_type = 'type'
        AND input_value = 'OTHER'
      THEN
        'OTHER'
    END AS document_type,
    CASE
      WHEN field_type = 'net' THEN input_value
    END AS net_income,
    CASE
      WHEN field_type = 'gross' THEN input_value
    END AS gross_income,
    CASE
      WHEN field_type = 'commited' THEN input_value
    END AS committed_income,
    CASE
      WHEN field_type = 'month' THEN input_value
    END AS reference_month,
    CASE
      WHEN field_type = 'date_start' THEN input_value
    END AS date_start,
    CASE
      WHEN field_type = 'date_end' THEN input_value
    END AS date_end,
    CASE
      WHEN field_type = 'date_start_partial' THEN input_value
    END AS date_start_partial,
    CASE
      WHEN field_type = 'date_end_partial' THEN input_value
    END AS date_end_partial,
    IF(
      field_type = 'fraud'
      AND input_value = TRUE,
      TRUE,
      FALSE
    ) AS is_fraud,
    IF(
      (
        field_type = 'is_partial'
        AND LOWER(TRIM(input_value)) LIKE '%sim%'
      ),
      TRUE,
      FALSE
    ) AS is_partial,
    ts_updated
  FROM
    extract_input_value
),
get_documents_annotation AS (
  SELECT
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    lead_time,
    document_name,
    document_path,
    MAX(document_type) AS document_type,
    SPLIT(MAX(net_income), ';') AS net_income,
    SPLIT(MAX(gross_income), ';') AS gross_income,
    SPLIT(MAX(committed_income), ';') AS committed_income,
    MAX(date_start) AS bank_statement_start_date,
    MAX(date_end) AS bank_statement_end_date,
    MAX(date_start_partial) AS bank_statement_date_start_partial,
    MAX(date_end_partial) AS bank_statement_date_end_partial,
    CASE
      WHEN MAX(document_type) = 'PAYSLIP' THEN SPLIT(MAX(reference_month), ';')
      ELSE ARRAY(0)
    END AS payslip_reference_period,
    MAX(is_partial) AS is_partial,
    is_fraud,
    ts_updated
  FROM
    get_input_value
  GROUP BY
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    lead_time,
    document_name,
    document_path,
    is_fraud,
    ts_updated
),
get_payslip_data AS (
  SELECT
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    lead_time,
    document_name,
    document_path,
    document_type,
    get_documents_annotation.net_income[0] AS net_income,
    get_documents_annotation.gross_income[0] AS gross_income,
    get_documents_annotation.committed_income[0] AS committed_income,
    get_documents_annotation.payslip_reference_period[0] AS payslip_reference_period,
    bank_statement_start_date,
    bank_statement_end_date,
    bank_statement_date_start_partial,
    bank_statement_date_end_partial,
    is_fraud,
    is_partial,
    ts_updated
  FROM
    get_documents_annotation
    LATERAL VIEW EXPLODE(net_income) AS net_income
    LATERAL VIEW EXPLODE(gross_income) AS gross_income
    LATERAL VIEW EXPLODE(committed_income) AS committed_income
    LATERAL VIEW EXPLODE(payslip_reference_period) AS payslip_reference_period
  WHERE
    document_type = 'PAYSLIP'
),
get_bank_statement_data AS (
  SELECT
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    lead_time,
    document_name,
    document_path,
    document_type,
    get_documents_annotation.net_income[0] AS net_income,
    get_documents_annotation.gross_income[0] AS gross_income,
    get_documents_annotation.committed_income[0] AS committed_income,
    get_documents_annotation.payslip_reference_period[0] AS payslip_reference_period,
    bank_statement_start_date,
    bank_statement_end_date,
    bank_statement_date_start_partial,
    bank_statement_date_end_partial,
    is_fraud,
    is_partial,
    ts_updated
  FROM
    get_documents_annotation
    LATERAL VIEW EXPLODE(net_income) AS net_income
    LATERAL VIEW EXPLODE(gross_income) AS gross_income
    LATERAL VIEW EXPLODE(committed_income) AS committed_income
    LATERAL VIEW EXPLODE(payslip_reference_period) AS payslip_reference_period
  WHERE
    document_type = 'BANK_STATEMENT'
),
union_documents AS (
  SELECT
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    lead_time,
    document_name,
    document_path,
    document_type,
    CASE
      WHEN net_income LIKE '%,%' THEN REGEXP_REPLACE(
        REGEXP_REPLACE(net_income, '\\.', ''),
        ',',
        '.'
      )
      ELSE net_income
    END AS net_income,
    CASE
      WHEN gross_income LIKE '%,%' THEN REGEXP_REPLACE(
        REGEXP_REPLACE(gross_income, '\\.', ''),
        ',',
        '.'
      )
      ELSE gross_income
    END AS gross_income,
    CASE
      WHEN committed_income LIKE '%,%' THEN REGEXP_REPLACE(
        REGEXP_REPLACE(committed_income, '\\.', ''),
        ',',
        '.'
      )
      ELSE committed_income
    END AS committed_income,
    payslip_reference_period,
    bank_statement_start_date,
    bank_statement_end_date,
    bank_statement_date_start_partial,
    bank_statement_date_end_partial,
    is_fraud,
    is_partial,
    ts_updated
  FROM
    get_payslip_data
  UNION ALL
  SELECT
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    lead_time,
    document_name,
    document_path,
    document_type,
    CASE
      WHEN net_income LIKE '%,%' THEN REGEXP_REPLACE(
        REGEXP_REPLACE(net_income, '\\.', ''),
        ',',
        '.'
      )
      ELSE net_income
    END AS net_income,
    CASE
      WHEN gross_income LIKE '%,%' THEN REGEXP_REPLACE(
        REGEXP_REPLACE(gross_income, '\\.', ''),
        ',',
        '.'
      )
      ELSE gross_income
    END AS gross_income,
    CASE
      WHEN committed_income LIKE '%,%' THEN REGEXP_REPLACE(
        REGEXP_REPLACE(committed_income, '\\.', ''),
        ',',
        '.'
      )
      ELSE committed_income
    END AS committed_income,
    payslip_reference_period,
    bank_statement_start_date,
    bank_statement_end_date,
    bank_statement_date_start_partial,
    bank_statement_date_end_partial,
    is_fraud,
    is_partial,
    ts_updated
  FROM
    get_bank_statement_data
)
SELECT
  DISTINCT CAST(id_task AS INT) AS id_task,
  CAST(id_project AS INT) AS id_project,
  CAST(id_proposal AS INT) AS id_proposal,
  CAST(id_completed_by AS INT) AS id_completed_by,
  proponent_cpf,
  LOWER(proponent_name) AS proponent_name,
  lead_time,
  document_name,
  document_path,
  document_type,
  CAST(net_income AS DECIMAL(10, 2)) AS net_income,
  CAST(gross_income AS DECIMAL(10, 2)) AS gross_income,
  CAST(committed_income AS DECIMAL(10, 2)) AS committed_income,
  payslip_reference_period,
  TO_DATE(bank_statement_start_date, 'dd/MM/yyyy') AS bank_statement_start_date,
  bank_statement_end_date,
  bank_statement_date_start_partial,
  TO_DATE(bank_statement_date_end_partial, 'dd/MM/yyyy') AS bank_statement_date_end_partial,
  is_fraud,
  is_partial,
  ts_updated,
  NOW() AS ts_load
FROM
  union_documents
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_task, document_name ORDER BY ts_updated DESC) = 1
