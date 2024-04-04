WITH get_credit_evaluations_count AS (
  SELECT
    id_proposal,
    COUNT(id) AS total_credit_evaluations,
    MAX(ts_created) AS ts_max_created
  FROM
    datalake_docx_clean.credit_evaluation
  GROUP BY id_proposal
),
proponent_incomes AS (
SELECT
  cep.id AS id_credit_evaluation_proponent,
  REPLACE(REPLACE(cep.cpf, ".", ""), "-", "") AS proponent_cpf,
  ce.id_proposal,
  ce.id_user,
  ce.id_house,
  cep.id_credit_evaluation,
  cep.resident,
  cec.total_credit_evaluations,
  IF(cep.proponent_type = 'USER', TRUE, FALSE) AS is_main_user,
  CAST(cep.monthly_income AS DOUBLE) AS proponent_monthly_income,
  CAST(pt.scr_income AS DOUBLE) AS proponent_scr_income,
  ce.ts_created AS ts_last_credit_evaluation
FROM
  datalake_docx_clean.credit_evaluation_proponent AS cep
LEFT JOIN
  datalake_sorting_hat_clean.proponent AS pt
    ON pt.cpf = cep.cpf
LEFT JOIN
  datalake_docx_clean.credit_evaluation AS ce
    ON ce.id = cep.id_credit_evaluation
    AND ce.id_proposal = pt.id_proposal
LEFT JOIN
  get_credit_evaluations_count AS cec
    ON cec.id_proposal = ce.id_proposal
-- Get the latest credit evaluation
WHERE ce.ts_created = cec.ts_max_created
),

get_proponent_income_data AS (
SELECT DISTINCT
  REPLACE(REPLACE(pd.cpf, ".", ""), "-", "") AS proponent_cpf,
  pd.id_context_external AS id_proposal,
  id.monthly_salary AS proponent_gross_income,
  id.verified_income AS proponent_verified_income
FROM
  datalake_docx.personal_documentation AS pd
LEFT JOIN
  datalake_docx.income_documentation AS id
    ON id.id_folder = pd.id_folder
    AND id.id_context_external = pd.id_context_external
WHERE
-- Get only tenant's data
  pd.document_context = 'Tenant'
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY pd.id_context_external, pd.cpf ORDER BY pd.ts_updated DESC) = 1
),

get_neoway_presumed_income AS (
  SELECT
    cpf,
    presumed_income AS presumed_income_neoway,
    ts_created AS ts_created_presumed_income_neoway,
    ts_updated AS ts_updated_presumed_income_neoway
  FROM
    datalake_arquivo_confidencial_clean.presumed_income_report
  WHERE
    source = 'NEOWAY'
),
get_transunion_presumed_income AS (
  SELECT
    cpf,
    presumed_income AS presumed_income_transunion,
    ts_created AS ts_created_presumed_income_transunion,
    ts_updated AS ts_updated_presumed_income_transunion
  FROM
    datalake_arquivo_confidencial_clean.presumed_income_report
  WHERE
    source = 'CRIVO'
),
join_presumed_income AS (
  SELECT
    DISTINCT coalesce(ni.cpf, ti.cpf) AS proponent_cpf,
    ni.presumed_income_neoway,
    ti.presumed_income_transunion
  FROM
    get_neoway_presumed_income AS ni
    LEFT JOIN
      get_transunion_presumed_income AS ti
        ON ti.cpf = ni.cpf
),

join_income_sources AS (
  SELECT
    pi.id_credit_evaluation_proponent,
    pi.proponent_cpf,
    pi.id_user,
    pi.id_credit_evaluation,
    pi.id_proposal,
    pi.proponent_monthly_income,
    pid.proponent_verified_income,
    pi.proponent_scr_income,
    pib.presumed_income_neoway,
    pib.presumed_income_transunion,
    pi.resident,
    pi.total_credit_evaluations,
    pi.is_main_user,
    pi.ts_last_credit_evaluation
  FROM
    proponent_incomes AS pi
  LEFT JOIN
    get_proponent_income_data AS pid
      ON pid.proponent_cpf = pi.proponent_cpf
      AND pid.id_proposal = pi.id_proposal
  LEFT JOIN
    join_presumed_income AS pib
      ON pib.proponent_cpf = pi.proponent_cpf
),

sum_proposal_incomes AS (
  SELECT
    id_proposal,
    SUM(proponent_monthly_income) AS sum_proponent_gross_income,
    SUM(presumed_income_neoway) AS sum_presumed_income_neoway,
    SUM(presumed_income_transunion) AS sum_presumed_income_transunion,
    SUM(proponent_scr_income) AS sum_scr_income,
    IF(
      SUM(presumed_income_neoway) > SUM(presumed_income_transunion),
      SUM(presumed_income_neoway),
      SUM(presumed_income_transunion)
    ) AS max_presumed_income_per_bureau
  FROM
    join_income_sources
  GROUP BY id_proposal
),

get_calculated_income AS (
  SELECT
    id_proposal,
    IF(
      COALESCE(max_presumed_income_per_bureau,0) > COALESCE(sum_scr_income,0),
      max_presumed_income_per_bureau,
      sum_scr_income
    ) AS calculated_income
  FROM
    sum_proposal_incomes
),

get_elected_income AS (
   SELECT
    ci.id_proposal,
    pi.sum_proponent_gross_income,
    ci.calculated_income,
    IF(
      ci.calculated_income > pi.sum_proponent_gross_income,
      ci.calculated_income,
      pi.sum_proponent_gross_income
    ) AS max_calculated_income,
    CAST(ci.calculated_income / pi.sum_proponent_gross_income AS DOUBLE) AS ratio_calculated_income
  FROM
    get_calculated_income AS ci
    LEFT JOIN
      sum_proposal_incomes AS pi
        ON ci.id_proposal = pi.id_proposal
),

income_sources AS (
  SELECT DISTINCT
    pis.id_credit_evaluation_proponent AS sk_credit_evaluation_proponent,
    pis.id_user AS sk_user,
    pis.id_credit_evaluation AS sk_credit_evaluation,
    pis.id_proposal AS sk_proposal,
    pis.proponent_cpf,
    pis.proponent_monthly_income,
    pis.proponent_scr_income,
    pis.proponent_verified_income,
    pis.presumed_income_neoway AS proponent_presumed_income_neoway,
    pis.presumed_income_transunion AS proponent_presumed_income_transunion,
    IF(ei.ratio_calculated_income >= 0.8, ei.sum_proponent_gross_income, ei.calculated_income) AS proposal_elected_income,
    pis.resident AS is_resident,
    pis.total_credit_evaluations,
    pis.is_main_user,
    pis.ts_last_credit_evaluation,
    NOW() AS ts_load
  FROM
    join_income_sources AS pis
  LEFT JOIN
    get_elected_income AS ei
      ON ei.id_proposal = pis.id_proposal
)
SELECT
  sk_credit_evaluation_proponent,
  sk_user,
  sk_credit_evaluation,
  sk_proposal,
  proponent_cpf,
  proponent_monthly_income,
  proponent_scr_income,
  proponent_verified_income,
  proponent_presumed_income_neoway,
  proponent_presumed_income_transunion,
  proposal_elected_income,
  total_credit_evaluations,
  is_main_user,
  is_resident,
  ts_last_credit_evaluation,
  ts_load
FROM
  income_sources
