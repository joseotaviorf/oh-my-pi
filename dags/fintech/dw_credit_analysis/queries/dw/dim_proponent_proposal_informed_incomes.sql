SELECT
  ce.id_proposal AS sk_proposal,
  REPLACE(REPLACE(cep.cpf, ".", ""), "-", "") AS proponent_cpf,
  cep.occupation_area,
  pt.income_nature,
  cep.proponent_type,
  cep.monthly_income AS proponent_monthly_income,
  cep.resident AS is_resident,
  cep.ts_created AS ts_informed_income,
  NOW() AS ts_load
FROM
  datalake_docx_clean.credit_evaluation_proponent AS cep
LEFT JOIN
  datalake_docx_clean.credit_evaluation AS ce
    ON ce.id = cep.id_credit_evaluation
LEFT JOIN
  datalake_sorting_hat_clean.proponent AS pt
    ON REPLACE(REPLACE(pt.cpf, ".", ""), "-", "") = REPLACE(REPLACE(cep.cpf, ".", ""), "-", "")
    AND pt.id_proposal = ce.id_proposal
WHERE
  ce.id_proposal IS NOT NULL
