SELECT
  e.id_case,
  e.id_invoice,
  e.id_agency,
  e.id_expense,
  IF(cacct.id_contract LIKE '%NVO_JUICIO%', ec.id_contract, cacct.id_contract) AS id_contract,
  c.id_dossier AS id_process,
  e.id_stage,
  cstg.stage_description AS stage_description,
  e.id_attorney,
  e.id_supervisor_attorney,
  e.invoice_description,
  c.process_type AS action,
  e.expense_type,
  e.expense_subtype,
  v.value_description AS expense_type_description,
  a.agency_name,
  c.debtor_name,
  e.case_type,
  e.expense_amount,
  e.expense_description,
  e.is_authorized,
  e.is_payment_made,
  e.is_reimbursed,
  e.dt_captured AS dt_lauch,
  e.dt_invoice AS dt_expense_real,
  e.dt_authorized,
  e.dt_reimbursed,
  e.dt_recovered
FROM datalake_cyber_legal_clean.case_expense AS e
LEFT JOIN
    datalake_cyber_legal_clean.text_content AS ec
        ON e.id_case = ec.id_case
LEFT JOIN
    datalake_cyber_legal_clean.case AS c
      ON e.id_case = c.id_case
LEFT JOIN
  datalake_cyber_legal_clean.values_list AS v
      ON e.expense_type = v.id_value
      AND e.expense_subtype = v.value_code
LEFT JOIN
    datalake_cyber_clean.agency AS a
      ON e.id_agency = a.id_agency
LEFT JOIN
    datalake_cyber_legal_clean.case_account AS cacct
      ON cacct.id_case = c.id_case
LEFT JOIN
  datalake_cyber_legal_clean.case_stage AS cstg
      ON cstg.id_case = e.id_case
        AND cstg.id_stage = e.id_stage
