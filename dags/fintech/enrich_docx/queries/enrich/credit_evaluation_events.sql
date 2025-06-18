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
get_credit_passport_events AS (
  SELECT DISTINCT
    NULL AS id_proposal,
    ce.id AS id_credit_evaluation,
    ce.id_group,
    ce.id_city,
    NULL AS id_house,
    ce.id_user,
    ce.scope,
    ce.result AS credit_result,
    ce.reason AS credit_result_reason,
    ce.status AS credit_evaluation_status,
    ce.limit_value AS user_requested_value,
    ce.pre_approved_limit AS user_pre_approved_limit,
    ces.credit_evaluation_source,
    NULL AS is_value_within_pre_approved_limit,
    NULL AS is_passport_missing,
    TRUE AS is_credit_passport,
    CASE
      WHEN ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status = 'PRE_REJECTED' THEN 'EVALUATION_NEGATIVE'
      WHEN ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status IN ('PRE_APPROVED', 'PRE_APPROVED_WITH_GUARANTEE') THEN 'EVALUATION_POSITIVE'
      WHEN ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status = 'BYPASSED' THEN 'BYPASSED'
    END AS event_name,
    CASE
      WHEN ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status = 'PRE_REJECTED' THEN ms.ts_created
    END AS ts_evaluation_negative,
    CASE
      WHEN ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status IN ('PRE_APPROVED', 'PRE_APPROVED_WITH_GUARANTEE') THEN ms.ts_created
    END AS ts_evaluation_positive,
    CASE
      WHEN ms.input_source_type = 'ANALYSIS_REQUEST'
      AND ms.status = 'BYPASSED' THEN ms.ts_created
    END AS ts_bypassed,
    ce.ts_created AS ts_credit_evaluation_created,
    NULL AS ts_credit_analysis_approved,
    NULL AS ts_docs_analysis,
    NULL AS ts_docs_resend,
    NULL AS ts_stand_by,
    ce.ts_expires AS ts_expired
  FROM
    datalake_docx_clean.credit_evaluation AS ce
  LEFT JOIN
    datalake_docx_clean.machine_state AS ms
      ON ms.id_credit_evaluation = ce.id
  LEFT JOIN
    get_credit_evaluation_source AS ces
      ON ces.id = ce.id
  WHERE
    ms.type = 'TENANT_GROUP_CREDIT' AND
    ce.scope = 'CITY' AND
    ms.status IN ('PRE_APPROVED', 'PRE_APPROVED_WITH_GUARANTEE', 'PRE_REJECTED', 'BYPASSED')
),
get_credit_evaluation_proposal_events AS (
  SELECT DISTINCT
    ce.id_proposal,
    ce.id AS id_credit_evaluation,
    ce.id_group,
    ce.id_city,
    ce.id_house,
    ce.id_user,
    ce.scope,
    ce.result AS credit_result,
    ce.reason AS credit_result_reason,
    ce.status AS credit_evaluation_status,
    ce.limit_value AS user_requested_value,
    ce.pre_approved_limit AS user_pre_approved_limit,
    'PROPOSAL_FLOW' AS credit_evaluation_source,
    IF(
      get_json_object(ce.early_result, '$[0].reason') = 'VALUE_WITHIN_PRE_APPROVED_LIMIT', TRUE, FALSE
    ) AS is_value_within_pre_approved_limit,
    False AS is_credit_passport,
    IF(ce.status = 'ON_HOLD' AND ce.early_result IS NULL, TRUE, FALSE) AS is_passport_missing,
    CASE
      WHEN
        ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
        AND ms.status = 'EVALUATION_NEGATIVE'
      THEN
        'EVALUATION_NEGATIVE'
      WHEN
        ms.input_source_type = 'CREDIT_ANALYSIS'
        AND ms.status IN ('EVALUATION_POSITIVE', 'EVALUATION_POSITIVE_WITH_GUARANTEE')
      THEN
        'EVALUATION_POSITIVE'
      WHEN
        get_json_object(ce.early_result, '$[0].reason') IN ('VALUE_EXCEEDS_CREDIT_LIMIT', 'VALUE_WITHIN_PRE_APPROVED_LIMIT')
      THEN
        'SUFFICIENT_CREDIT_LIMIT'
      WHEN
        ms.input_source_type IN ('TENANT', 'ANALYST')
        AND ms.status = 'DOCS_ANALYSIS'
      THEN
        'DOCS_ANALYSIS'
      WHEN
        ms.input_source_type IN ('ANALYST', 'EMAIL_VALIDATION_SERVICE')
        AND ms.status = 'DOCS_RESEND'
      THEN
        'DOCS_RESEND'
      WHEN
        ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
        AND ms.status = 'APPROVED'
      THEN
        'CREDIT_ANALYSIS_APPROVED'
      WHEN
        ms.input_source_type = 'ANALYST'
        AND ms.status = 'STAND_BY'
      THEN
        'STAND_BY'
      WHEN
        get_json_object(ce.early_result, '$[0].reason') IN (
          'CLEAR_NO',
          'BLOCKLIST',
          'PENDING_INVOICES',
          'SCOPE_NOT_EVALUATED'
        )
      THEN
        'EVALUATION_NEGATIVE'
    END AS event_name,
    NULL AS ts_bypassed,
    ce.ts_created AS ts_credit_evaluation_created,
    CASE
      WHEN
        ms.input_source_type = 'CREDIT_ANALYSIS'
        AND ms.status IN ('EVALUATION_POSITIVE', 'EVALUATION_POSITIVE_WITH_GUARANTEE')
      THEN
        ms.ts_created
    END AS ts_evaluation_positive,
    CASE
      WHEN
        ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
        AND ms.status = 'APPROVED'
      THEN
        ms.ts_created
    END AS ts_credit_analysis_approved,
    CASE
      WHEN
        ms.input_source_type IN ('TENANT', 'ANALYST')
        AND ms.status = 'DOCS_ANALYSIS'
      THEN
        ms.ts_created
    END AS ts_docs_analysis,
    CASE
      WHEN
        ms.input_source_type IN ('ANALYST', 'EMAIL_VALIDATION_SERVICE')
        AND ms.status = 'DOCS_RESEND'
      THEN
        ms.ts_created
    END AS ts_docs_resend,
    CASE
      WHEN
        ms.input_source_type = 'ANALYST'
        AND ms.status = 'STAND_BY'
      THEN
        ms.ts_created
    END AS ts_stand_by,
    CASE
      WHEN
        ms.input_source_type IN ('CREDIT_ANALYSIS', 'ANALYST')
        AND ms.status = 'EVALUATION_NEGATIVE'
      THEN
        ms.ts_created
    END AS ts_evaluation_negative,
    ce.ts_expires AS ts_expired
  FROM
    datalake_docx_clean.credit_evaluation AS ce
      LEFT JOIN datalake_docx_clean.machine_state AS ms
        ON ms.id_context_external = ce.id_proposal
  WHERE
    ms.type = 'TENANT'
    AND ms.status IN (
      'EVALUATION_NEGATIVE',
      'APPROVED',
      'EVALUATION_POSITIVE',
      'EVALUATION_POSITIVE_WITH_GUARANTEE',
      'DOCS_ANALYSIS',
      'DOCS_RESEND',
      'STAND_BY',
      'NOT_SENT'
    )
    AND (ce.scope = 'HOUSE' OR ce.scope IS NULL)
    AND ce.status <> 'FAILED'
),
union_credit_evaluations AS (
SELECT
  id_proposal,
  id_credit_evaluation,
  id_group,
  id_city,
  id_house,
  id_user,
  scope,
  credit_result,
  credit_result_reason,
  credit_evaluation_status,
  credit_evaluation_source,
  user_requested_value,
  user_pre_approved_limit,
  event_name,
  is_value_within_pre_approved_limit,
  is_passport_missing,
  is_credit_passport,
  ts_credit_evaluation_created,
  ts_bypassed,
  ts_evaluation_positive,
  ts_evaluation_negative,
  ts_credit_analysis_approved,
  ts_docs_analysis,
  ts_docs_resend,
  ts_stand_by,
  ts_expired
FROM get_credit_passport_events

UNION ALL

SELECT
  id_proposal,
  id_credit_evaluation,
  id_group,
  id_city,
  id_house,
  id_user,
  scope,
  credit_result,
  credit_result_reason,
  credit_evaluation_status,
  credit_evaluation_source,
  user_requested_value,
  user_pre_approved_limit,
  event_name,
  is_value_within_pre_approved_limit,
  is_passport_missing,
  is_credit_passport,
  ts_credit_evaluation_created,
  ts_bypassed,
  ts_evaluation_positive,
  ts_evaluation_negative,
  ts_credit_analysis_approved,
  ts_docs_analysis,
  ts_docs_resend,
  ts_stand_by,
  ts_expired
FROM get_credit_evaluation_proposal_events
)
SELECT
  id_proposal,
  id_credit_evaluation,
  id_group,
  id_city,
  id_house,
  id_user,
  scope,
  credit_result,
  credit_result_reason,
  credit_evaluation_status,
  credit_evaluation_source,
  user_requested_value,
  user_pre_approved_limit,
  event_name,
  is_value_within_pre_approved_limit,
  is_passport_missing,
  is_credit_passport,
  ts_credit_evaluation_created,
  ts_bypassed,
  ts_evaluation_positive,
  ts_evaluation_negative,
  ts_credit_analysis_approved,
  ts_docs_analysis,
  ts_docs_resend,
  ts_stand_by,
  ts_expired
FROM
  union_credit_evaluations
WHERE event_name IS NOT NULL
