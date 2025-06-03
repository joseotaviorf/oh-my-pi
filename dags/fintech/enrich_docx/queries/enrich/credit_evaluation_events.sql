WITH get_credit_evaluation_events AS (
  SELECT
    IF(ms.input_source_type = 'CREDIT_EVALUATION', ms.id_input_source, ms.id_credit_evaluation) AS id_credit_evaluation,
    ms.id_context_external AS id_proposal,
    ms.id_group,
    ms.id_city,
    ga.id_house AS id_listing_authorization,
    ga.status AS group_authorization_status,
    CASE
      WHEN
        ms.type = 'TENANT_GROUP_CREDIT' AND
        ms.input_source_type = 'PERSON_UUID' AND
        ms.status = 'PRE_EVALUATION_STARTED'
      THEN
        'PRE_EVALUATION_STARTED'
      WHEN
        ms.type = 'TENANT_GROUP_CREDIT' AND
        ms.input_source_type = 'ANALYSIS_REQUEST' AND
        ms.status = 'PRE_REJECTED'
      THEN
        'PRE_REJECTED'
      WHEN
        ms.type = 'TENANT_GROUP_CREDIT' AND
        ms.input_source_type = 'ANALYSIS_REQUEST' AND
        ms.status IN ('PRE_APPROVED', 'PRE_APPROVED_WITH_GUARANTEE')
      THEN
        'PRE_APPROVED'
      WHEN
        ms.type = 'TENANT_GROUP_CREDIT' AND
        ms.input_source_type = 'ANALYSIS_REQUEST' AND
        ms.status = 'BYPASSED'
      THEN
        'BYPASSED'
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type IN  ('CREDIT_EVALUATION', 'OFFER', 'TENANT')
        AND ms.status IN ('EVALUATION_STARTED', 'NOT_SENT')
      THEN
        'EVALUATION_STARTED'
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type = 'CREDIT_ANALYSIS'
        AND ms.status IN ('EVALUATION_POSITIVE', 'EVALUATION_POSITIVE_WITH_GUARANTEE')
      THEN
        'EVALUATION_POSITIVE'
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
        AND ms.status = 'APPROVED'
      THEN
        'CREDIT_ANALYSIS_APPROVED'
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
        AND ms.status = 'EVALUATION_NEGATIVE'
      THEN
        'EVALUATION_NEGATIVE'
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type IN ('TENANT', 'ANALYST')
        AND ms.status = 'DOCS_ANALYSIS'
      THEN
        'DOCS_ANALYSIS'
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type IN ('ANALYST', 'EMAIL_VALIDATION_SERVICE')
        AND ms.status = 'DOCS_RESEND'
      THEN
        'DOCS_RESEND'
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type = 'ANALYST'
        AND ms.status = 'STAND_BY'
      THEN
        'STAND_BY'
    END AS event_name,
    CASE
      WHEN
        ms.type = 'TENANT_GROUP_CREDIT' AND
        ms.input_source_type = 'PERSON_UUID' AND
        ms.status = 'PRE_EVALUATION_STARTED'
      THEN
        ms.ts_created
    END AS ts_pre_evaluation_started,
    CASE
      WHEN
        ms.type = 'TENANT_GROUP_CREDIT' AND
        ms.input_source_type = 'ANALYSIS_REQUEST' AND
        ms.status = 'PRE_REJECTED'
      THEN
        ms.ts_created
    END AS ts_pre_rejected,
    CASE
      WHEN
        ms.type = 'TENANT_GROUP_CREDIT' AND
        ms.input_source_type = 'ANALYSIS_REQUEST' AND
        ms.status IN ('PRE_APPROVED', 'PRE_APPROVED_WITH_GUARANTEE')
      THEN
        ms.ts_created
    END AS ts_pre_approved,
    CASE
      WHEN
        ms.type = 'TENANT_GROUP_CREDIT' AND
        ms.input_source_type = 'ANALYSIS_REQUEST' AND
        ms.status = 'BYPASSED'
      THEN
        ms.ts_created
    END AS ts_bypassed,
    CASE
      WHEN
        get_json_object(ga.credit_result, '$.reason') = 'VALUE_WITHIN_PRE_APPROVED_LIMIT' AND
        ga.status = 'ISSUED'
      THEN
        ga.ts_created
    END AS ts_sufficient_credit_limit,
    CASE
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type IN  ('CREDIT_EVALUATION', 'OFFER', 'TENANT')
        AND ms.status IN ('EVALUATION_STARTED', 'NOT_SENT')
      THEN
        ms.ts_created
    END AS ts_evaluation_started,
    CASE
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type = 'CREDIT_ANALYSIS'
        AND ms.status IN ('EVALUATION_POSITIVE', 'EVALUATION_POSITIVE_WITH_GUARANTEE')
      THEN
        ms.ts_created
    END AS ts_evaluation_positive,
    CASE
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
        AND ms.status = 'APPROVED'
      THEN
        ms.ts_created
    END AS ts_credit_analysis_approved,
    CASE
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
        AND ms.status = 'EVALUATION_NEGATIVE'
      THEN
        ms.ts_created
    END AS ts_evaluation_negative,
    CASE
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type IN ('TENANT', 'ANALYST')
        AND ms.status = 'DOCS_ANALYSIS'
      THEN
        ms.ts_created
    END AS ts_docs_analysis,
    CASE
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type IN ('ANALYST', 'EMAIL_VALIDATION_SERVICE')
        AND ms.status = 'DOCS_RESEND'
      THEN
        ms.ts_created
    END AS ts_docs_resend,
    CASE
      WHEN
        ms.type = 'TENANT' AND
        ms.input_source_type = 'ANALYST'
        AND ms.status = 'STAND_BY'
      THEN
        ms.ts_created
    END AS ts_stand_by,
    IF(
      get_json_object(ga.credit_result, '$.reason') = 'VALUE_WITHIN_PRE_APPROVED_LIMIT', TRUE, FALSE
    ) AS is_value_within_pre_approved_limit,
    ms.ts_created,
    ga.ts_created AS ts_group_authorization_created
  FROM
    datalake_docx_clean.machine_state AS ms
      LEFT JOIN datalake_docx_clean.group_authorization AS ga
        ON ms.id_group = ga.id_group
        AND get_json_object(credit_result, '$.scopeId') = ms.id_scope
  WHERE
    ms.input_source_type != 'RECOVERY'
), get_credit_evaluation AS (
SELECT DISTINCT
  ce.id AS id_credit_evaluation,
  ce.id_proposal,
  ce.id_group,
  ce.id_city,
  COALESCE(pa.id_listing_authorization, ce.id_house) AS id_house,
  ce.id_user,
  pa.group_authorization_status,
  pa.event_name,
  CASE
    WHEN ce.id_proposal IS NOT NULL AND ce.id_group IS NULL AND p.proposal_source IS NULL THEN 'NORMAL_FLOW'
    WHEN p.proposal_source = 'DEFAULT' THEN 'NORMAL_FLOW'
    WHEN p.proposal_source = 'PASSPORT' THEN 'POS_OFFER_PASSPORT_FLOW'
    WHEN ce.id_group IS NOT NULL AND ce.id_proposal IS NULL AND p.proposal_source IS NULL THEN 'PRE_OFFER_PASSPORT_FLOW'
  END AS credit_evaluation_source,
  pa.is_value_within_pre_approved_limit,
  pa.ts_pre_evaluation_started,
  pa.ts_pre_rejected,
  pa.ts_pre_approved,
  pa.ts_bypassed,
  pa.ts_sufficient_credit_limit,
  pa.ts_evaluation_started,
  pa.ts_evaluation_positive,
  pa.ts_credit_analysis_approved,
  pa.ts_evaluation_negative,
  pa.ts_docs_analysis,
  pa.ts_docs_resend,
  pa.ts_stand_by,
  pa.ts_created,
  pa.ts_group_authorization_created,
  ce.ts_created AS ts_credit_evaluation_created
FROM
  get_credit_evaluation_events AS pa
  LEFT JOIN
    datalake_docx_clean.credit_evaluation AS ce
    ON pa.id_credit_evaluation = ce.id
    OR pa.id_proposal = ce.id_proposal
  LEFT JOIN
    datalake_sorting_hat_clean.proposal AS p
    ON ce.id_proposal = p.id
)
SELECT
  id_credit_evaluation,
  id_proposal,
  id_group,
  id_city,
  id_house,
  id_user,
  group_authorization_status,
  event_name,
  credit_evaluation_source,
  is_value_within_pre_approved_limit,
  ts_pre_evaluation_started,
  ts_pre_rejected,
  ts_pre_approved,
  ts_bypassed,
  ts_sufficient_credit_limit,
  ts_evaluation_started,
  ts_evaluation_positive,
  ts_credit_analysis_approved,
  ts_evaluation_negative,
  ts_docs_analysis,
  ts_docs_resend,
  ts_stand_by,
  ts_group_authorization_created,
  ts_created AS ts_machine_state_created,
  ts_credit_evaluation_created,
  ROW_NUMBER() OVER (PARTITION BY id_group, id_proposal ORDER BY ts_created,ts_group_authorization_created) AS event_order
FROM
  get_credit_evaluation
WHERE
id_credit_evaluation IS NOT NULL
