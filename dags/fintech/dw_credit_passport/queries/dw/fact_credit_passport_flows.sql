WITH get_all_passport_events AS (
  SELECT
    cee.id_credit_evaluation,
    cee.id_proposal,
    cee.id_group,
    cee.id_user,
    cee.id_city,
    cee.credit_evaluation_source,
    fce.decision_reason,
    g.is_active AS is_group_active,
    cee.ts_expired,
    cee.ts_credit_evaluation_created,
    DATE(cee.ts_credit_evaluation_created) AS dt_credit_passport,
    1 AS evaluation_started,
    CASE
      WHEN fce.is_bypass THEN 1
      ELSE 0
    END AS bypass,
    CASE
      WHEN cee.ts_evaluation_positive IS NOT NULL THEN 1
      WHEN fce.is_bypass THEN 1
      ELSE 0
    END AS evaluation_positive,
    CASE
      WHEN cee.ts_evaluation_negative IS NOT NULL THEN 1
      ELSE 0
    END AS evaluation_negative
  FROM
    datalake_docx.credit_evaluation_events AS cee
      LEFT JOIN dw_credit_passport.fact_credit_evaluation AS fce
        ON fce.sk_credit_evaluation = cee.id_credit_evaluation
      LEFT JOIN datalake_docx_clean.group AS g
        ON g.id_group = cee.id_group
  WHERE
    TRUE
    AND cee.is_credit_passport = TRUE
    AND cee.ts_credit_evaluation_created >= DATE '2025-06-02'
),
get_user_first_touchpoint AS (
  SELECT
    id_user,
    IF(credit_evaluation_source = 'PRE_OFFER_PASSPORT_FLOW', 'listing', 'offer') AS user_first_touchpoint
  FROM
    get_all_passport_events
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY ts_credit_evaluation_created ASC) = 1
),
get_all_proposal_events AS (
  SELECT DISTINCT
    cee.id_credit_evaluation,
    COALESCE(get_json_object(ce.early_result, '$[0].creditEvaluationId'), ar.id_external) AS id_credit_passport,
    cee.id_proposal,
    cee.id_group,
    cee.id_user,
    cee.id_city,
    flrf.sk_offer,
    flrf.sk_contract,
    cee.credit_evaluation_source,
    fce.decision_reason,
    fce.documentation_policy_type,
    CASE
      WHEN flrf.sk_offer_approved_date > 1 THEN 1
      ELSE 0
    END AS offer_approved,
    1 AS evaluation_started,
    CASE
      WHEN cee.ts_evaluation_positive IS NOT NULL THEN 1
      ELSE 0
    END AS evaluation_positive,
    CASE
      WHEN cee.ts_evaluation_negative IS NOT NULL THEN 1
      ELSE 0
    END AS evaluation_negative,
    CASE
      WHEN cee.is_value_within_pre_approved_limit = TRUE THEN 1
      ELSE 0
    END AS sufficient_credit_limit,
    CASE
      WHEN cee.ts_docs_analysis IS NOT NULL THEN 1
      ELSE 0
    END AS document_sent,
    CASE
      WHEN cee.ts_credit_analysis_approved IS NOT NULL THEN 1
      ELSE 0
    END AS credit_analysis_approved,
    CASE
      WHEN flrf.sk_contract_created_date > 0 THEN 1
      ELSE 0
    END AS contract_created,
    CASE
      WHEN flrf.sk_contract_signed_date > 0 THEN 1
      ELSE 0
    END AS contract_signed,
    cee.ts_credit_evaluation_created
  FROM
    datalake_docx.credit_evaluation_events AS cee
      LEFT JOIN dw_rent.fact_listing_rent_flows AS flrf
        ON (
          cee.id_proposal IS NOT NULL
          AND cee.id_proposal = flrf.sk_proposal
        )
      LEFT JOIN dw_credit_passport.fact_credit_evaluation AS fce
        ON (cee.id_credit_evaluation = fce.sk_credit_evaluation)
      LEFT JOIN datalake_docx_clean.credit_evaluation AS ce
        ON (ce.id = cee.id_credit_evaluation)
        AND ce.scope = 'HOUSE'
      LEFT JOIN datalake_sorting_hat_clean.analysis_request AS ar
        ON ar.id = ce.analysis_request_id
        AND ar.external_source = 'CREDIT_EVALUATION'
  WHERE
    TRUE
    AND cee.is_credit_passport = FALSE
    AND cee.id_group IS NOT NULL
    AND cee.id_city IS NOT NULL
    AND cee.ts_credit_evaluation_created >= DATE '2025-06-02'
),
get_proposal_funnel_step AS (
  SELECT
    id_credit_evaluation,
    id_credit_passport,
    id_proposal,
    id_group,
    id_user,
    id_city,
    sk_offer,
    sk_contract,
    credit_evaluation_source,
    decision_reason,
    documentation_policy_type,
    MAX(offer_approved) AS offer_approved,
    MAX(evaluation_started) AS evaluation_started,
    MAX(evaluation_positive) AS evaluation_positive,
    MAX(evaluation_negative) AS evaluation_negative,
    MAX(sufficient_credit_limit) AS sufficient_credit_limit,
    MAX(document_sent) AS document_sent,
    MAX(credit_analysis_approved) AS credit_analysis_approved,
    MAX(contract_created) AS contract_created,
    MAX(contract_signed) AS contract_signed,
    ts_credit_evaluation_created
  FROM
    get_all_proposal_events
  GROUP BY
    ALL
),
join_events AS (
  SELECT
    COALESCE(gpfs.id_credit_evaluation, gpe.id_credit_evaluation) AS id_credit_evaluation,
    gpfs.id_credit_passport,
    COALESCE(gpfs.id_proposal, -1) AS id_proposal,
    COALESCE(gpfs.id_group, gpe.id_group) AS id_group,
    COALESCE(gpfs.id_user, gpe.id_user) AS id_user,
    COALESCE(gpfs.id_city, gpe.id_city) AS id_city,
    COALESCE(gpfs.sk_offer, -1) AS sk_offer,
    COALESCE(gpfs.sk_contract, -1) AS sk_contract,
    COALESCE(
      gpe.credit_evaluation_source, gpfs.credit_evaluation_source
    ) AS credit_evaluation_source,
    ft.user_first_touchpoint,
    gpfs.documentation_policy_type,
    COALESCE(gpfs.decision_reason, gpe.decision_reason) AS decision_reason,
    COALESCE(gpfs.offer_approved, 0) AS offer_approved,
    COALESCE(gpfs.evaluation_started, gpe.evaluation_started) AS evaluation_started,
    COALESCE(gpfs.evaluation_positive, gpe.evaluation_positive) AS evaluation_positive,
    COALESCE(gpe.bypass, 0) AS bypass,
    COALESCE(gpfs.evaluation_negative, gpe.evaluation_negative) AS evaluation_negative,
    COALESCE(gpfs.sufficient_credit_limit, 0) AS sufficient_credit_limit,
    COALESCE(gpfs.document_sent, 0) AS document_sent,
    COALESCE(gpfs.credit_analysis_approved, 0) AS credit_analysis_approved,
    COALESCE(gpfs.contract_created, 0) AS contract_created,
    COALESCE(gpfs.contract_signed, 0) AS contract_signed,
    gpe.is_group_active,
    gpe.dt_credit_passport,
    gpe.ts_expired,
    COALESCE(
      gpfs.ts_credit_evaluation_created, gpe.ts_credit_evaluation_created
    ) AS ts_credit_evaluation_created
  FROM
    get_all_passport_events AS gpe
      LEFT JOIN get_proposal_funnel_step AS gpfs
        ON (gpe.id_credit_evaluation = gpfs.id_credit_passport)
      LEFT JOIN get_user_first_touchpoint AS ft
        ON (ft.id_user = gpe.id_user)
),
add_group_last_credit_evaluation AS (
  SELECT
    id_credit_evaluation AS sk_credit_evaluation,
    CAST(COALESCE(id_credit_passport, id_credit_evaluation) AS BIGINT) AS sk_credit_passport,
    id_group AS sk_group,
    id_user AS sk_user,
    id_city AS sk_city,
    sk_offer,
    id_proposal AS sk_proposal,
    sk_contract,
    credit_evaluation_source,
    user_first_touchpoint,
    decision_reason,
    documentation_policy_type,
    CASE
      WHEN contract_signed = 1 THEN 'G. contract_signed'
      WHEN contract_created = 1 THEN 'F. contract_created'
      WHEN credit_analysis_approved = 1 THEN 'E. credit_analysis_approved'
      WHEN document_sent = 1 THEN 'D. document_sent'
      WHEN sufficient_credit_limit = 1 THEN 'C. sufficient_credit_limit'
      WHEN evaluation_positive = 1 THEN 'B. evaluation_positive'
      WHEN evaluation_started = 1 THEN 'A. evaluation_started'
    END AS funnel_step,
    offer_approved,
    evaluation_started,
    evaluation_positive,
    evaluation_negative,
    bypass,
    sufficient_credit_limit,
    document_sent,
    credit_analysis_approved,
    contract_created,
    contract_signed,
    is_group_active,
    CASE
      WHEN
        is_group_active = TRUE
        AND ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY ts_credit_evaluation_created DESC) = 1
      THEN
        TRUE
      ELSE FALSE
    END as is_group_last_credit_evaluation,
    dt_credit_passport,
    ts_expired,
    ts_credit_evaluation_created
  FROM
    join_events
),
add_maximum_funnel_step AS (
  SELECT
    sk_credit_evaluation,
    sk_credit_passport,
    sk_group,
    sk_user,
    sk_city,
    sk_offer,
    sk_proposal,
    sk_contract,
    credit_evaluation_source,
    user_first_touchpoint,
    decision_reason,
    documentation_policy_type,
    funnel_step,
    offer_approved,
    evaluation_started,
    evaluation_positive,
    evaluation_negative,
    bypass,
    sufficient_credit_limit,
    document_sent,
    credit_analysis_approved,
    contract_created,
    contract_signed,
    is_group_active,
    is_group_last_credit_evaluation,
    CASE
      WHEN ROW_NUMBER() OVER (PARTITION BY sk_user, date_trunc('MONTH', dt_credit_passport) ORDER BY funnel_step DESC, ts_credit_evaluation_created DESC) = 1 THEN TRUE
      ELSE FALSE
    END AS is_user_version,
    dt_credit_passport,
    ts_expired,
    ts_credit_evaluation_created,
    NOW() AS ts_load
  FROM
    add_group_last_credit_evaluation
)
  SELECT
    sk_credit_evaluation,
    sk_credit_passport,
    sk_group,
    sk_user,
    sk_city,
    sk_offer,
    sk_proposal,
    sk_contract,
    credit_evaluation_source,
    user_first_touchpoint,
    decision_reason,
    documentation_policy_type,
    funnel_step,
    offer_approved,
    evaluation_started,
    evaluation_positive,
    evaluation_negative,
    bypass,
    sufficient_credit_limit,
    document_sent,
    credit_analysis_approved,
    contract_created,
    contract_signed,
    is_group_active,
    is_user_version,
    is_group_last_credit_evaluation,
    dt_credit_passport,
    ts_expired,
    ts_credit_evaluation_created,
    ts_load
  FROM
    add_maximum_funnel_step
