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
      from_json(
        get_json_object(task_completion.result, "$"),
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
    task_completion.ts_updated
  FROM
    datalake_quinturk_clean.project
      INNER JOIN datalake_quinturk_clean.task
        ON project.id == task.id_project
      INNER JOIN datalake_quinturk_clean.task_completion
        ON task_completion.id_task = task.id
  WHERE
    title like "%[DocPilot] Auditoria%"
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
    REGEXP_REPLACE(
      get_json_object(to_json(input_answer), "$.from_name"), '[A-Za-z_]+$', ""
    ) AS document_name,
    REGEXP_REPLACE(
      get_json_object(to_json(input_answer), "$.from_name"), '^document_[0-9]+_', ""
    ) AS field_type,
    REPLACE(
      COALESCE(
        get_json_object(to_json(input_answer), "$.value.choices[0]"),
        get_json_object(to_json(input_answer), "$.value.text[0]")
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
        AND lower(trim(input_value)) LIKE '%sim%'
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
    ALL
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
    document_type,
    POSEXPLODE(net_income) AS (idx, net_income),
    POSEXPLODE(gross_income) AS (idx2, gross_income),
    POSEXPLODE(committed_income) AS (idx3, committed_income),
    POSEXPLODE(payslip_reference_period) AS (idx4, payslip_reference_period),
    bank_statement_start_date,
    bank_statement_end_date,
    bank_statement_date_start_partial,
    bank_statement_date_end_partial,
    is_fraud,
    is_partial,
    ts_updated
  FROM
    get_documents_annotation
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
    document_type,
    POSEXPLODE(net_income) AS (idx, net_income),
    POSEXPLODE(gross_income) AS (idx2, gross_income),
    POSEXPLODE(committed_income) AS (idx3, committed_income),
    POSEXPLODE(payslip_reference_period) AS (idx4, payslip_reference_period),
    bank_statement_start_date,
    bank_statement_end_date,
    bank_statement_date_start_partial,
    bank_statement_date_end_partial,
    is_fraud,
    is_partial,
    ts_updated
  FROM
    get_documents_annotation
  WHERE
    document_type = 'BANK_STATEMENT'
),
handle_payslip AS (
  SELECT
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    lead_time,
    document_name,
    document_type,
    payslip_reference_period,
    net_income,
    gross_income,
    committed_income,
    bank_statement_start_date,
    bank_statement_end_date,
    bank_statement_date_start_partial,
    bank_statement_date_end_partial,
    is_fraud,
    is_partial,
    ts_updated
  FROM
    get_payslip_data
  WHERE
    idx = idx2
    AND idx = idx3
    AND idx = idx4
),
handle_bank_statement AS (
  SELECT
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    lead_time,
    document_name,
    document_type,
    net_income,
    gross_income,
    committed_income,
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
  WHERE
    idx = idx2
    AND idx = idx3
    AND idx = idx4
),
union_documents as (
  SELECT
    id_task,
    id_project,
    id_proposal,
    id_completed_by,
    proponent_cpf,
    proponent_name,
    lead_time,
    document_name,
    document_type,
    net_income,
    gross_income,
    committed_income,
    payslip_reference_period,
    bank_statement_start_date,
    bank_statement_end_date,
    bank_statement_date_start_partial,
    bank_statement_date_end_partial,
    is_fraud,
    is_partial,
    ts_updated
  FROM
    handle_payslip
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
    document_type,
    net_income,
    gross_income,
    committed_income,
    payslip_reference_period,
    bank_statement_start_date,
    bank_statement_end_date,
    bank_statement_date_start_partial,
    bank_statement_date_end_partial,
    is_fraud,
    is_partial,
    ts_updated
  FROM
    handle_bank_statement
)
SELECT
  CAST(id_task AS INT) AS id_task,
  CAST(id_project AS INT) AS id_project,
  CAST(id_proposal AS INT) AS id_proposal,
  CAST(id_completed_by AS INT) AS id_completed_by,
  proponent_cpf,
  lower(proponent_name) AS proponent_name,
  lead_time,
  document_name,
  document_type,
  ROUND(CAST(net_income AS DECIMAL), 2) AS net_income,
  ROUND(CAST(gross_income AS DECIMAL), 2) AS gross_income,
  ROUND(CAST(committed_income AS DECIMAL), 2) AS committed_income,
  payslip_reference_period,
  to_date(bank_statement_start_date, 'dd/MM/yyyy')AS bank_statement_start_date,
  to_date(bank_statement_end_date, 'dd/MM/yyyy') AS bank_statement_end_date,
  bank_statement_date_start_partial,
  to_date(bank_statement_date_end_partial, 'dd/MM/yyyy')AS bank_statement_date_end_partial,
  is_fraud,
  is_partial,
  ts_updated,
  NOW() AS ts_load
FROM
  union_documents
