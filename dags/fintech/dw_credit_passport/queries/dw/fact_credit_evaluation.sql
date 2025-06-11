WITH credit_evaluation AS (
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
  IF(
    ce.status IN ('PROCESSING', 'NOT_SENT', 'ON_HOLD', 'CANCELLED', 'FAILED'),
    'RESULT_PENDING',
    ce.result
  ) AS credit_evaluation_result,
  COALESCE(
    ce.early_result_guarantee_type, get_json_object(ce.early_result, '$[0].result')
  ) AS pre_evaluation_result,
  IF(
    ce.status IN ('PROCESSING', 'NOT_SENT', 'ON_HOLD', 'CANCELLED', 'FAILED'),
    'REASON_PENDING',
    ce.reason
  ) AS decision_reason,
  ce.type AS documentation_policy_type,
  ce.pre_approved_limit,
  ce.limit_value,
  CASE
    WHEN
      ga.requestor_type = 'TRANSACT_FLOW'
      OR ce.scope = 'HOUSE'
    THEN
      'POS_OFFER_PASSPORT_FLOW'
    WHEN ce.scope = 'CITY' THEN 'PRE_OFFER_PASSPORT_FLOW'
    WHEN
      ce.scope IS NULL
      AND ce.id_proposal IS NULL
      AND ce.id_group IS NULL
    THEN
      'EARLY_CREDIT_FLOW'
    ELSE 'NORMAL_FLOW'
  END AS credit_evaluation_source,
  CASE
    WHEN
      ce.proponent_group_type = 'MYSELF'
      OR pp.is_single_tenant = TRUE
    THEN
      'SINGLE'
    WHEN
      ce.proponent_group_type = 'OTHERS'
      OR pt.proposal_proponent_type = 'PERSON'
    THEN
      'OTHERS'
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
  coalesce(ce.automatic, ce.is_automatic) AS is_automatic,
  IF(
    ce.id_group IS NULL
    AND ce.id_proposal IS NULL,
    TRUE,
    FALSE
  ) AS is_early_credit,
  IF(ce.scope IS NOT NULL, TRUE, FALSE) is_credit_passport,
  IF(
    ce.status IN ('ON_HOLD', 'FAILED', 'CANCELLED')
    AND get_json_object(ga.credit_result, '$.reason') = 'VALUE_EXCEEDS_CREDIT_LIMIT',
    TRUE,
    FALSE
  ) AS is_value_exceeding_credit_limit,
  IF(eval.rank = 1, TRUE, FALSE) AS is_most_recent_evaluation,
  IF(
    ce.scope = 'HOUSE'
    AND ce.id_group IS NULL,
    TRUE,
    FALSE
  ) AS is_passport_missing,
  ce.ts_created,
  ce.ts_updated,
  ce.ts_expires AS ts_expired,
  NOW() AS ts_load
FROM
  datalake_docx_clean.credit_evaluation AS ce
    LEFT JOIN datalake_docx_clean.group_authorization AS ga
      ON ce.id_group = ga.id_group
      AND ce.id_house = ga.id_house
      and ga.status = 'ISSUED'
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
