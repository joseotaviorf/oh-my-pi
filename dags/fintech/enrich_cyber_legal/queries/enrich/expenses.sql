SELECT
  e.id_case,
  e.id_agency,
  a.agency_name,
  c.debtor_name,
  e.case_type,
  e.expense_amount,
  v.value_description AS expense_type_description,
  e.expense_description,
  e.dt_reimbursed
FROM datalake_cyber_legal_homolog_clean.case_expense AS e
LEFT JOIN
    datalake_cyber_legal_homolog_clean.case AS c
      ON e.id_case = c.id_case
LEFT JOIN
  datalake_cyber_legal_homolog_clean.values_list AS v
    ON e.expense_type = v.id_value
      AND e.expense_subtype = v.value_code
LEFT JOIN
    datalake_cyber_clean.agency AS a
      ON e.id_agency = a.id_agency
WHERE is_authorized IS TRUE
  AND is_reimbursed IS TRUE
