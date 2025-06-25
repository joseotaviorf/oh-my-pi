WITH get_credit_evaluation_source AS (
SELECT
   MIN(DATE_TRUNC('day', ce.ts_created)) AS day,
   ce.id,
   CASE
     WHEN
       MIN(cep.ts_created) IS NULL
       OR MIN(ce.ts_updated) < MIN(cep.ts_created)
     THEN
       'PRE_OFFER_PASSPORT_FLOW'
     ELSE 'POS_OFFER_PASSPORT_FLOW'
   END AS credit_evaluation_source
 FROM
   datalake_docx_clean.credit_evaluation ce
     LEFT JOIN datalake_docx_clean.credit_evaluation_aud cea
       ON cea.scope = 'HOUSE'
       AND cea.id_group = ce.id_group
       AND cea.id_city = ce.id_city
     LEFT JOIN datalake_docx_clean.credit_evaluation cep
       ON cep.id = cea.id_credit_evaluation
 WHERE
   ce.scope = 'CITY'
 GROUP BY
   ce.id
),
credit_evaluation AS (
  SELECT
    cep.id_credit_evaluation,
    ce.id_user,
    ce.id_proposal,
    cep.proponent_type
  FROM
    datalake_docx_clean.credit_evaluation_proponent AS cep
      LEFT JOIN datalake_docx_clean.credit_evaluation AS ce
        ON cep.id_credit_evaluation = ce.id
  -- removing legacy data (latest record is 2021)
  WHERE
    cep.proponent_type IS NOT NULL
),
evaluations AS (
  SELECT
    id AS id_credit_evaluation,
    id_group,
    id_user,
    ts_created,
    RANK() OVER (PARTITION BY id_user, id_group ORDER BY ts_created DESC) AS rank
  FROM
    datalake_docx_clean.credit_evaluation
),
proposal_proponent_type AS (
  SELECT
    id_proposal,
    MAX(proponent_type) AS proposal_proponent_type
  FROM
    credit_evaluation
  GROUP BY
    id_proposal
),
proposal_proponents AS (
  SELECT
    id_proposal,
    COUNT(DISTINCT cpf) AS total_proposal_proponents,
    IF(COUNT(DISTINCT cpf) = 1, TRUE, FALSE) AS is_single_tenant
  FROM
    datalake_sorting_hat_clean.proponent
  GROUP BY
    id_proposal
),
group_proponents AS (
  SELECT
    id_group,
    count(id_reference) AS total_group_proponents
  FROM
    datalake_docx_clean.group_member
  GROUP BY
    id_group
)
SELECT DISTINCT
  ce.id AS sk_credit_evaluation,
  ce.id_group AS sk_group,
  ce.id_proposal AS sk_proposal,
  ce.id_user AS sk_user,
  ce.id_house AS sk_house,
  ce.id_city AS sk_city,
  ce.scope,
  ce.status AS credit_evaluation_status,
  CASE
    WHEN ce.status IN ('PROCESSING', 'NOT_SENT', 'ON_HOLD', 'CANCELLED', 'FAILED') THEN 'REASON_PENDING'
    ELSE ce.result
  END AS credit_evaluation_result,
  COALESCE(
    ce.early_result_guarantee_type, get_json_object(ce.early_result, '$[0].result')
  ) AS pre_evaluation_result,
  CASE
    WHEN (ce.reason = 'PRE_APPROVAL_POLICY' AND ce.result = 'PRE_APPROVED') OR ce.result = 'PRE_APPROVED' THEN 'FREE'
    WHEN ce.early_result_guarantee_type = 'FREE' OR get_json_object(ce.early_result, '$[0].result') = 'FREE' THEN 'FREE'
    WHEN ce.reason = 'PRE_APPROVAL_POLICY' AND ce.result = 'PRE_APPROVED_WITH_GUARANTEE' THEN 'PAID'
    WHEN ce.early_result_guarantee_type = 'PRO_GUARANTOR' OR get_json_object(ce.early_result, '$[0].result') IN (
      'PRO_GUARANTOR', 'THIRD_PARTY_GUARANTEE', 'STANDALONE', 'PRO_GUARANTOR_OR_DEPOSIT', 'DEPOSIT', 'INSURANCE_OR_DEPOSIT', 'RENTAL_GUARANTEE'
      ) THEN 'PAID'
    WHEN ce.status IN ('PROCESSING', 'NOT_SENT', 'ON_HOLD', 'CANCELLED', 'FAILED') THEN 'REASON_PENDING'
  ELSE ce.reason
  END AS decision_reason,
  ce.type AS documentation_policy_type,
  ce.pre_approved_limit AS user_pre_approved_limit,
  CAST(ce.limit_value AS DECIMAL(10,2)) AS user_requested_value,
  cen.total_informed_income,
  cen.debit_limit AS maximum_debit_limit,
  CASE
    WHEN
      ces.credit_evaluation_source IS NOT NULL
    THEN
      ces.credit_evaluation_source
    WHEN
      ce.scope IS NULL
      AND ce.id_proposal IS NULL
      AND ce.id_group IS NULL
    THEN
      'EARLY_CREDIT_FLOW'
    ELSE 'PROPOSAL_FLOW'
  END AS credit_evaluation_source,
  CASE
    WHEN
      ce.proponent_group_type = 'MYSELF'
      OR pp.is_single_tenant = TRUE
    THEN
      'SINGLE_TENANT'
    WHEN
      ce.proponent_group_type = 'OTHERS'
      OR pt.proposal_proponent_type = 'PERSON'
    THEN
      'RENTING_FOR_OTHERS'
    WHEN
      ce.proponent_group_type = 'MYSELF_WITH_OTHERS'
      OR gp.total_group_proponents > 1
      OR pp.total_proposal_proponents > 1
    THEN
      'MULTI_TENANT'
  END group_type,
  get_json_object(pr.raw_data, '$.variant') AS variant,
  get_json_object(pr.result, '$.policy_dti') AS policy_dti,
  get_json_object(pr.result, '$.analysis_category') AS category,
  get_json_object(pr.result, '$.risk_category_canon') AS risk_category_canon,
  COALESCE(pp.total_proposal_proponents, gp.total_group_proponents) AS number_of_proponents,
  ce.is_automatic,
  IF(
    ce.id_group IS NULL
    AND ce.id_proposal IS NULL,
    TRUE,
    FALSE
  ) AS is_early_credit,
  IF(ce.scope = 'CITY', TRUE, FALSE) is_credit_passport,
  IF(eval.rank = 1, TRUE, FALSE) AS is_most_recent_evaluation,
  IF(ce.result = 'BYPASSED', TRUE, FALSE) is_bypass,
  ce.ts_created,
  ce.ts_updated,
  ce.ts_expires AS ts_expired,
  NOW() AS ts_load
FROM
  datalake_docx_clean.credit_evaluation AS ce
    LEFT JOIN proposal_proponent_type AS pt
      ON ce.id_proposal = pt.id_proposal
    LEFT JOIN proposal_proponents AS pp
      ON ce.id_proposal = pp.id_proposal
    LEFT JOIN group_proponents AS gp
      ON ce.id_group = gp.id_group
    LEFT JOIN evaluations AS eval
      ON ce.id = eval.id_credit_evaluation
    LEFT JOIN datalake_sorting_hat_clean.policy_report AS pr
      ON pr.id_external = ce.id
      AND pr.type = 'CREDIT_POLICY'
    LEFT JOIN get_credit_evaluation_source AS ces
      ON ces.id = ce.id
    LEFT JOIN datalake_credit_analysis.credit_engine AS cen
      ON ce.id = cen.id_credit_evaluation
      AND cen.group_name = 'PRE_APPROVAL_LIMIT_POLICY'
