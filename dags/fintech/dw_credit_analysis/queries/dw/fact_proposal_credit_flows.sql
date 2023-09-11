WITH credit_analysis AS (
  SELECT
    id_credit_analysis,
    id_proposal,
    category,
    max_ca_category
  FROM
    datalake_credit_analysis.credit_analysis
),
early_credit_analysis AS (
  SELECT
    ec.id_user,
    ec.id_house,
    MIN(DATE(ec.ts_early_credit_analysis_created)) AS dt_created,
    MAX(DATE(ec.ts_early_credit_analysis_expired)) AS dt_expired
  FROM
    datalake_credit_analysis.early_credit_analysis AS ec
  LEFT JOIN
    dw_public.dim_house_listing AS hl
      ON ec.id_house = hl.id_house
  WHERE
    hl.country_code = 'BR'
    AND hl.rental_administrator = 'QUINTOANDAR'
  GROUP BY
    ec.id_user,
    ec.id_house
),
rent_flows AS (
  SELECT
    flrf.sk_client,
    flrf.sk_house_listing,
    CAST(flrf.sk_house_listing / 1000 AS INTEGER) AS sk_house,
    flrf.sk_contract_signed_date,
    CAST(COALESCE(ca.id_credit_analysis, -1) AS INTEGER) AS sk_credit_analysis,
    flrf.sk_credit_analysis_approved_date,
    COALESCE(
      NULLIF(flrf.sk_last_credit_evaluation_positive, -1),
      CASE
        WHEN flrf.sk_last_credit_evaluation_positive < 0
        AND flrf.sk_last_credit_evaluation_negative > 0
        AND ca.category IS NOT NULL THEN flrf.sk_last_credit_evaluation_negative
      END,
      -1
    ) AS sk_credit_evaluation_approved_date,
    CAST(
      COALESCE(cap.id_first_credit_analysis, -1) AS INTEGER
    ) AS sk_first_credit_analysis,
    CAST(COALESCE(cap.id_first_variant, -1) AS INTEGER) AS sk_first_variant,
    CAST(
      COALESCE(cap.id_last_variant_not_null, -1) AS INTEGER
    ) AS sk_last_variant_not_null,
    COALESCE(ca.category, -1) AS sk_guarantee_category,
    flrf.sk_guarantee_paid_date,
    CAST(
      COALESCE(cap.id_last_credit_analysis, -1) AS INTEGER
    ) AS sk_last_credit_analysis,
    flrf.sk_last_credit_evaluation_init,
    flrf.sk_last_credit_evaluation_negative,
    flrf.sk_last_credit_evaluation_positive,
    flrf.sk_offer,
    flrf.sk_offer_approved_date,
    flrf.sk_offer_submitted_date,
    cap.id_proposal AS sk_proposal,
    flrf.sk_region,
    flrf.sk_tenant_doc_complete_date,
    flrf.sk_tenant_first_doc_sent_date,
    flrf.funnel_step,
    IF(
      cap.id_first_credit_analysis = ca.id_credit_analysis,
      TRUE,
      FALSE
    ) AS is_first_credit_evaluation,
    IF(
      cap.id_last_credit_analysis = ca.id_credit_analysis,
      TRUE,
      FALSE
    ) AS is_last_credit_evaluation,
    dd.date AS dt_offer_submitted
  FROM
    dw_public.fact_listing_rent_flows AS flrf
  LEFT JOIN
    datalake_credit_analysis.credit_analysis_proposals AS cap
      ON cap.id_proposal = flrf.sk_proposal
  LEFT JOIN
    credit_analysis AS ca
      ON cap.id_proposal = ca.id_proposal
  LEFT JOIN
    dw_public.dim_date AS dd 
      ON flrf.sk_offer_submitted_date = dd.sk_date
),
proposal_credit_flows AS (
  SELECT
    rf.sk_client,
    rf.sk_house_listing,
    rf.sk_house,
    rf.sk_contract_signed_date,
    rf.sk_credit_analysis,
    rf.sk_credit_analysis_approved_date,
    rf.sk_credit_evaluation_approved_date,
    rf.sk_first_credit_analysis,
    rf.sk_first_variant,
    rf.sk_last_variant_not_null,
    rf.sk_guarantee_category,
    rf.sk_guarantee_paid_date,
    rf.sk_last_credit_analysis,
    rf.sk_last_credit_evaluation_init,
    rf.sk_last_credit_evaluation_negative,
    rf.sk_last_credit_evaluation_positive,
    rf.sk_offer,
    rf.sk_offer_approved_date,
    rf.sk_offer_submitted_date,
    rf.sk_proposal,
    rf.sk_region,
    rf.sk_tenant_doc_complete_date,
    rf.sk_tenant_first_doc_sent_date,
    rf.funnel_step,
    CAST(
      COALESCE(
        REGEXP_REPLACE(CAST(eca.dt_created AS VARCHAR(8)), '-', ''),
        -1
      ) AS INTEGER
    ) AS sk_ec_created_date,
    CAST(
      COALESCE(
        REGEXP_REPLACE(CAST(eca.dt_expired AS VARCHAR(8)), '-', ''),
        -1
      ) AS INTEGER
    ) AS sk_ec_expired_date,
    rf.is_first_credit_evaluation,
    rf.is_last_credit_evaluation,
    CASE
      WHEN rf.dt_offer_submitted
        BETWEEN eca.dt_created
        AND eca.dt_expired
      THEN TRUE
      ELSE FALSE
    END AS has_early_credit,
    eca.dt_created AS dt_ec_created,
    eca.dt_expired AS dt_ec_expired,
    rf.dt_offer_submitted
  FROM
    rent_flows AS rf
  LEFT JOIN
    early_credit_analysis AS eca
      ON rf.sk_client = eca.id_user
      AND rf.sk_house = eca.id_house
)
SELECT
  sk_client,
  sk_house_listing,
  sk_house,
  sk_contract_signed_date,
  sk_credit_analysis,
  sk_credit_analysis_approved_date,
  sk_credit_evaluation_approved_date,
  sk_first_credit_analysis,
  sk_first_variant,
  sk_last_variant_not_null,
  sk_guarantee_category,
  sk_guarantee_paid_date,
  sk_last_credit_analysis,
  sk_last_credit_evaluation_init,
  sk_last_credit_evaluation_negative,
  sk_last_credit_evaluation_positive,
  sk_offer,
  sk_offer_approved_date,
  sk_offer_submitted_date,
  sk_proposal,
  sk_region,
  sk_tenant_doc_complete_date,
  sk_tenant_first_doc_sent_date,
  sk_ec_created_date,
  sk_ec_expired_date,
  funnel_step,
  is_first_credit_evaluation,
  is_last_credit_evaluation,
  has_early_credit,
  NOW() AS ts_load
FROM
  proposal_credit_flows
WHERE
  sk_last_credit_evaluation_init > 0
  AND sk_proposal > 0