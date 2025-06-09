WITH get_credit_evaluation AS (
  SELECT
    DISTINCT ce.id AS id_credit_evaluation,
    ce.id_proposal,
    ce.id_group,
    ce.id_city,
    ce.id_house,
    ce.id_user,
    ce.scope,
    ce.result AS credit_result,
    ce.reason AS credit_result_reason,
    ce.status AS credit_evaluation_status,
    'POS_OFFER_PASSPORT_FLOW' AS credit_evaluation_source,
    ga.status AS group_authorization_status,
    IF(
      get_json_object(ga.credit_result, '$.reason') = 'VALUE_WITHIN_PRE_APPROVED_LIMIT',
      TRUE,
      FALSE
    ) AS is_value_within_pre_approved_limit,
    ce.ts_created AS ts_credit_evaluation_created
  FROM
    datalake_docx_clean.credit_evaluation AS ce
    LEFT JOIN datalake_docx_clean.group_authorization AS ga ON ce.id_group = ga.id_group
    AND ce.id_house = ga.id_house
  WHERE
    ga.requestor_type = 'TRANSACT_FLOW'
  UNION ALL
  SELECT
    id AS id_credit_evaluation,
    id_proposal,
    id_group,
    id_city,
    id_house,
    id_user,
    scope,
    result AS credit_result,
    reason AS credit_result_reason,
    status AS credit_evaluation_status,
    IF(scope = 'CITY', 'PRE_OFFER_PASSPORT_FLOW', 'NORMAL_FLOW') AS credit_evaluation_source,
    NULL AS group_authorization_status,
    NULL AS is_value_within_pre_approved_limit,
    ts_created AS ts_credit_evaluation_created
  from
    datalake_docx_clean.credit_evaluation
  WHERE
    scope <> 'HOUSE'
    OR scope IS NULL
),
get_credit_evaluation_events AS (
  SELECT
    IF(
      ms.input_source_type = 'CREDIT_EVALUATION',
      ms.id_input_source,
      ms.id_credit_evaluation
    ) AS id_credit_evaluation,
    ms.id_context_external AS id_proposal,
    ms.id_group,
    ms.id_city,
    CASE
      WHEN ms.type = 'TENANT_GROUP_CREDIT'
      AND ms.input_source_type = 'PERSON_UUID'
      AND ms.status = 'PRE_EVALUATION_STARTED' THEN 'PRE_EVALUATION_STARTED'
      WHEN ms.type = 'TENANT_GROUP_CREDIT'
      AND ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status = 'PRE_REJECTED' THEN 'PRE_REJECTED'
      WHEN ms.type = 'TENANT_GROUP_CREDIT'
      AND ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status IN ('PRE_APPROVED', 'PRE_APPROVED_WITH_GUARANTEE') THEN 'PRE_APPROVED'
      WHEN ms.type = 'TENANT_GROUP_CREDIT'
      AND ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status = 'BYPASSED' THEN 'BYPASSED'
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('CREDIT_EVALUATION', 'OFFER', 'TENANT')
      AND ms.status IN ('EVALUATION_STARTED', 'NOT_SENT') THEN 'EVALUATION_STARTED'
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type = 'CREDIT_ANALYSIS'
      AND ms.status IN (
        'EVALUATION_POSITIVE',
        'EVALUATION_POSITIVE_WITH_GUARANTEE'
      ) THEN 'EVALUATION_POSITIVE'
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
      AND ms.status = 'APPROVED' THEN 'CREDIT_ANALYSIS_APPROVED'
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
      AND ms.status = 'EVALUATION_NEGATIVE' THEN 'EVALUATION_NEGATIVE'
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('TENANT', 'ANALYST')
      AND ms.status = 'DOCS_ANALYSIS' THEN 'DOCS_ANALYSIS'
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('ANALYST', 'EMAIL_VALIDATION_SERVICE')
      AND ms.status = 'DOCS_RESEND' THEN 'DOCS_RESEND'
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type = 'ANALYST'
      AND ms.status = 'STAND_BY' THEN 'STAND_BY'
    END AS event_name,
    CASE
      WHEN ms.type = 'TENANT_GROUP_CREDIT'
      AND ms.input_source_type = 'PERSON_UUID'
      AND ms.status = 'PRE_EVALUATION_STARTED' THEN ms.ts_created
    END AS ts_pre_evaluation_started,
    CASE
      WHEN ms.type = 'TENANT_GROUP_CREDIT'
      AND ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status = 'PRE_REJECTED' THEN ms.ts_created
    END AS ts_pre_rejected,
    CASE
      WHEN ms.type = 'TENANT_GROUP_CREDIT'
      AND ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status IN ('PRE_APPROVED', 'PRE_APPROVED_WITH_GUARANTEE') THEN ms.ts_created
    END AS ts_pre_approved,
    CASE
      WHEN ms.type = 'TENANT_GROUP_CREDIT'
      AND ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status = 'BYPASSED' THEN ms.ts_created
    END AS ts_bypassed,
    CASE
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('CREDIT_EVALUATION', 'OFFER', 'TENANT')
      AND ms.status IN ('EVALUATION_STARTED', 'NOT_SENT') THEN ms.ts_created
    END AS ts_evaluation_started,
    CASE
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type = 'CREDIT_ANALYSIS'
      AND ms.status IN (
        'EVALUATION_POSITIVE',
        'EVALUATION_POSITIVE_WITH_GUARANTEE'
      ) THEN ms.ts_created
    END AS ts_evaluation_positive,
    CASE
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
      AND ms.status = 'APPROVED' THEN ms.ts_created
    END AS ts_credit_analysis_approved,
    CASE
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
      AND ms.status = 'EVALUATION_NEGATIVE' THEN ms.ts_created
    END AS ts_evaluation_negative,
    CASE
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('OFFER', 'TENANT')
      AND ms.status = 'NOT_SENT' THEN ms.ts_created
    END AS ts_state_machine_start,
    CASE
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('TENANT', 'ANALYST')
      AND ms.status = 'DOCS_ANALYSIS' THEN ms.ts_created
    END AS ts_docs_analysis,
    CASE
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type IN ('ANALYST', 'EMAIL_VALIDATION_SERVICE')
      AND ms.status = 'DOCS_RESEND' THEN ms.ts_created
    END AS ts_docs_resend,
    CASE
      WHEN ms.type = 'TENANT'
      AND ms.input_source_type = 'ANALYST'
      AND ms.status = 'STAND_BY' THEN ms.ts_created
    END AS ts_stand_by,
    IF(
      ms.input_source_type IN ('CREDIT_EVALUATION', 'OFFER', 'TENANT')
      AND ms.status = 'NOT_SENT',
      TRUE,
      FALSE
    ) AS is_not_sent,
    ms.ts_created
  FROM
    datalake_docx_clean.machine_state AS ms
  WHERE
    ms.input_source_type != 'RECOVERY'
),
handle_evaluation_negative AS (
  SELECT
    ce.id_credit_evaluation,
    ce.id_proposal,
    ce.id_group,
    ce.id_city,
    ce.id_house,
    ce.id_user,
    ce.scope,
    ce.credit_evaluation_status,
    ce.credit_evaluation_source,
    ce.group_authorization_status,
    IF(
      cev.is_not_sent = TRUE
      AND ce.is_value_within_pre_approved_limit = FALSE
      AND ce.credit_evaluation_status IN ('ON_HOLD', 'FAILED', 'CANCELLED'),
      'EVALUATION_NEGATIVE',
      cev.event_name
    ) AS event_name,
    ce.is_value_within_pre_approved_limit,
    cev.ts_pre_evaluation_started,
    cev.ts_pre_rejected,
    cev.ts_pre_approved,
    cev.ts_bypassed,
    cev.ts_state_machine_start,
    cev.ts_evaluation_started,
    cev.ts_evaluation_positive,
    IF(
      cev.is_not_sent = TRUE,
      cev.ts_state_machine_start,
      cev.ts_evaluation_negative
    ) AS ts_evaluation_negative,
    cev.ts_credit_analysis_approved,
    cev.ts_docs_analysis,
    cev.ts_docs_resend,
    cev.ts_stand_by,
    ce.ts_credit_evaluation_created
  FROM
    get_credit_evaluation AS ce
    LEFT JOIN get_credit_evaluation_events AS cev ON cev.id_credit_evaluation = ce.id_credit_evaluation
    OR cev.id_proposal = ce.id_proposal
  WHERE
    cev.event_name IS NOT NULL
    AND cev.is_not_sent = TRUE
),
join_credit_evaluation_events AS (
  SELECT
    ce.id_credit_evaluation,
    ce.id_proposal,
    ce.id_group,
    ce.id_city,
    ce.id_house,
    ce.id_user,
    ce.scope,
    ce.credit_evaluation_status,
    ce.credit_evaluation_source,
    ce.group_authorization_status,
    cev.event_name,
    ce.is_value_within_pre_approved_limit,
    cev.ts_pre_evaluation_started,
    cev.ts_pre_rejected,
    cev.ts_pre_approved,
    cev.ts_bypassed,
    cev.ts_state_machine_start,
    cev.ts_evaluation_started,
    cev.ts_evaluation_positive,
    cev.ts_evaluation_negative,
    cev.ts_credit_analysis_approved,
    cev.ts_docs_analysis,
    cev.ts_docs_resend,
    cev.ts_stand_by,
    ce.ts_credit_evaluation_created
  FROM
    get_credit_evaluation AS ce
    LEFT JOIN get_credit_evaluation_events AS cev ON cev.id_credit_evaluation = ce.id_credit_evaluation
    OR cev.id_proposal = ce.id_proposal
  WHERE
    cev.event_name IS NOT NULL
),
union_all AS (
  SELECT
    id_credit_evaluation,
    id_proposal,
    id_group,
    id_city,
    id_house,
    id_user,
    scope,
    credit_evaluation_status,
    credit_evaluation_source,
    group_authorization_status,
    event_name,
    is_value_within_pre_approved_limit,
    ts_pre_evaluation_started,
    ts_pre_rejected,
    ts_pre_approved,
    ts_bypassed,
    ts_state_machine_start,
    ts_evaluation_started,
    ts_evaluation_positive,
    ts_evaluation_negative,
    ts_credit_analysis_approved,
    ts_docs_analysis,
    ts_docs_resend,
    ts_stand_by,
    ts_credit_evaluation_created
  FROM
    join_credit_evaluation_events
  UNION ALL
  SELECT
    id_credit_evaluation,
    id_proposal,
    id_group,
    id_city,
    id_house,
    id_user,
    scope,
    credit_evaluation_status,
    credit_evaluation_source,
    group_authorization_status,
    event_name,
    is_value_within_pre_approved_limit,
    ts_pre_evaluation_started,
    ts_pre_rejected,
    ts_pre_approved,
    ts_bypassed,
    ts_state_machine_start,
    ts_evaluation_started,
    ts_evaluation_positive,
    ts_evaluation_negative,
    ts_credit_analysis_approved,
    ts_docs_analysis,
    ts_docs_resend,
    ts_stand_by,
    ts_credit_evaluation_created
  FROM
    handle_evaluation_negative
)
SELECT
    id_credit_evaluation,
    id_proposal,
    id_group,
    id_city,
    id_house,
    id_user,
    scope,
    credit_evaluation_status,
    credit_evaluation_source,
    group_authorization_status,
    event_name,
    is_value_within_pre_approved_limit,
    ts_pre_evaluation_started,
    ts_pre_rejected,
    ts_pre_approved,
    ts_bypassed,
    ts_state_machine_start,
    ts_evaluation_started,
    ts_evaluation_positive,
    ts_evaluation_negative,
    ts_credit_analysis_approved,
    ts_docs_analysis,
    ts_docs_resend,
    ts_stand_by,
    ts_credit_evaluation_created
FROM
  union_all
