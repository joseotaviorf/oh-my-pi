WITH dw_last_proposal AS (
  SELECT
    sk_pre_analysis,
    sk_offer,
    sk_proposal,
    financing_value,
    credit_analysis_status,
    ts_max_credit_application_approval,
    is_most_advanced,
    ts_last_updated
  FROM (
    SELECT
      fpp.sk_pre_analysis,
      fpp.sk_offer,
      dp.sk_proposal,
      dp.financing_value,
      dp.credit_application_status AS credit_analysis_status,
      fpp.ts_max_credit_application_approval,
      fpp.is_most_advanced,
      fpp.ts_last_updated,
      ROW_NUMBER() OVER (PARTITION BY fpp.sk_pre_analysis ORDER BY fpp.sk_proposal_status DESC, fpp.ts_last_updated DESC) AS _w,
      fpp.sk_proposal_status
    FROM dw_atta.fact_pre_analysis_proposal_flow AS fpp
    LEFT JOIN dw_atta.dim_proposal_atta AS dp
      ON fpp.sk_proposal = dp.sk_proposal
    WHERE
      dp.sk_proposal > 0 AND fpp.is_most_advanced = 1 AND fpp.sk_offer <> '-1'
  ) AS _t
  WHERE
    _w = 1
), dim_financed_proposal AS (
  SELECT
    fpp.sk_offer,
    cd.sk_pre_analysis,
    cd.sk_proposal,
    cd.financing_value,
    cd.ts_last_updated,
    CASE
      WHEN NOT CAST(cd.ts_max_credit_application_approval AS DATE) IS NULL
      THEN TRUE
      ELSE FALSE
    END AS is_proposal_approved,
    COUNT(DISTINCT fpp.sk_proposal) AS total_proposal,
    COUNT(
      DISTINCT CASE
        WHEN dp.credit_application_status = 'Approved'
        THEN fpp.sk_proposal
        ELSE NULL
      END
    ) AS proposal_approved,
    COUNT(
      DISTINCT CASE
        WHEN dp.credit_application_status = 'Reproved'
        THEN fpp.sk_proposal
        ELSE NULL
      END
    ) AS proposal_reproved,
    COUNT(
      DISTINCT CASE
        WHEN dp.credit_application_status = 'Incomplete'
        OR dp.credit_application_status IS NULL
        THEN fpp.sk_proposal
        ELSE NULL
      END
    ) AS proposal_pending,
    MIN(CAST(fpp.ts_registration AS DATE)) AS first_pre_analysis,
    MIN(CAST(fpp.ts_credit_started AS DATE)) AS first_credit_started,
    MIN(CAST(fpp.ts_min_credit_application_approval AS DATE)) AS first_credit_approved_date,
    MAX(CAST(fpp.ts_max_credit_application_approval AS DATE)) AS last_credit_approved_date,
    MAX(CAST(fpp.ts_credit_ended AS DATE)) AS credit_ended_isolve,
    MAX(CAST(fpp.ts_credit_ended AS DATE)) AS credit_ended_date,
    MAX(COALESCE(CAST(fpp.ts_credit_ended AS DATE), CAST(fpp.ts_credit_ended AS DATE))) AS last_credit_ended,
    MIN(DATE_TRUNC('DAY', fpp.ts_min_inspection)) AS first_dt_inspection,
    MIN(DATE_TRUNC('DAY', fpp.ts_max_inspection)) AS last_dt_inspection,
    MIN(DATE_TRUNC('DAY', fpp.ts_min_checklist)) AS first_dt_checklist,
    MAX(DATE_TRUNC('DAY', fpp.ts_max_checklist)) AS last_dt_checklist,
    MIN(DATE_TRUNC('DAY', fpp.ts_bank_legal_analysis_started)) AS first_dt_bank_legal_analysis_started,
    MAX(DATE_TRUNC('DAY', fpp.ts_bank_legal_analysis_ended)) AS last_dt_bank_legal_analysis_ended,
    MIN(DATE_TRUNC('DAY', fpp.ts_min_financing_contract)) AS first_dt_financing_contract,
    MAX(DATE_TRUNC('DAY', fpp.ts_max_financing_contract)) AS last_dt_financing_contract,
    MIN(DATE_TRUNC('DAY', fpp.ts_min_contracted)) AS first_dt_contracted,
    MAX(DATE_TRUNC('DAY', fpp.ts_max_contracted)) AS last_dt_contracted,
    MIN(DATE_TRUNC('DAY', fpp.ts_financing_started)) AS first_financing_started,
    MAX(CAST(fpp.ts_financing_ended AS DATE)) AS last_financing_ended
  FROM dw_atta.fact_pre_analysis_proposal_flow AS fpp
  LEFT JOIN dw_atta.dim_proposal_atta AS dp
    ON fpp.sk_proposal = dp.sk_proposal
  LEFT JOIN dw_last_proposal AS cd
    ON fpp.sk_pre_analysis = cd.sk_pre_analysis
  WHERE
    fpp.sk_proposal > 0 AND fpp.sk_offer <> '-1'
  GROUP BY
    fpp.sk_offer,
    cd.sk_pre_analysis,
    cd.sk_proposal,
    cd.financing_value,
    cd.ts_last_updated,
    cd.ts_max_credit_application_approval
)
SELECT
  fo.sk_offer,
  ca.sk_pre_analysis,
  ca.sk_proposal,
  fo.sk_closing_specialist,
  fo.sk_buyer,
  fo.sk_owner,
  ca.financing_value,
  CASE
    WHEN NOT COALESCE(ca.last_credit_ended, ca.credit_ended_date) IS NULL
    THEN '1'
    ELSE NULL
  END AS internal_vendors_flag,
  fo.days_offer_accepted_to_sale_agreement_signed,
  fo.days_offer_submitted_to_offer_accepted,
  fo.days_offer_submitted_to_sale_agreement_signed,
  DATEDIFF(TO_DATE(ca.last_credit_approved_date), TO_DATE(fo.ts_offer_submitted)) AS days_offer_submitted_to_credit_approved,
  DATEDIFF(TO_DATE(ca.last_credit_ended), TO_DATE(fo.ts_offer_submitted)) AS days_offer_submitted_to_credit_ended,
  DATEDIFF(TO_DATE(ca.last_financing_ended), TO_DATE(fo.ts_offer_submitted)) AS days_offer_submitted_to_financing_ended,
  DATEDIFF(TO_DATE(ca.last_financing_ended), TO_DATE(ca.last_credit_ended)) AS days_credit_ended_to_financing_ended,
  DATEDIFF(TO_DATE(ca.last_financing_ended), TO_DATE(ca.last_credit_approved_date)) AS days_credit_approved_to_financing_ended,
  DATEDIFF(TO_DATE(ca.last_credit_approved_date), TO_DATE(fo.ts_sale_agreement_signed)) AS days_CCV_to_credit_approved,
  DATEDIFF(TO_DATE(ca.last_credit_ended), TO_DATE(fo.ts_sale_agreement_signed)) AS days_CCV_to_credit_ended,
  DATEDIFF(TO_DATE(ca.last_financing_ended), TO_DATE(fo.ts_sale_agreement_signed)) AS days_CCV_to_financing_ended,
  fo.ts_offer_submitted AS ts_offer_sumitted,
  fo.ts_offer_accepted AS ts_offer_accepted,
  fo.ts_sale_agreement_signed AS ts_ccv_signed,
  ca.first_pre_analysis AS dt_first_pre_analysis,
  ca.first_credit_started AS dt_credit_started,
  ca.first_credit_approved_date AS dt_credit_approved,
  ca.credit_ended_date AS dt_credit_ended,
  ca.first_dt_inspection AS ts_first_inspection,
  ca.last_dt_inspection AS ts_last_inspection,
  ca.first_dt_checklist AS ts_first_checklist,
  ca.last_dt_checklist AS ts_last_checklist,
  ca.first_dt_bank_legal_analysis_started AS ts_first_bank_legal_analysis_started,
  ca.last_dt_bank_legal_analysis_ended AS ts_last_bank_legal_analysis_ended,
  ca.first_dt_financing_contract AS ts_first_financing_contract,
  ca.last_dt_financing_contract AS ts_last_financing_contract,
  ca.first_dt_contracted AS ts_first_contracted,
  ca.last_dt_contracted AS ts_last_contracted,
  ca.first_financing_started AS ts_first_financing_started,
  ca.last_financing_ended AS dt_financing_ended,
  ca.ts_last_updated AS ts_last_updated_isolve,
  DATE_TRUNC('WEEK', fo.ts_offer_submitted) AS dt_offer_submitted_week,
  DATE_TRUNC('WEEK', fo.ts_offer_accepted) AS dt_offer_accepted_week,
  DATE_TRUNC('WEEK', fo.ts_sale_agreement_signed) AS dt_ccv_signed_week,
  NOW() AS ts_load
FROM dw_sale.fact_offers AS fo
LEFT JOIN dw_sale.dim_sale_agreement AS dsa
  ON fo.sk_offer = dsa.sk_offer
LEFT JOIN dim_financed_proposal AS ca
  ON fo.sk_offer = ca.sk_offer
WHERE
  fo.ts_offer_submitted >= CAST('2023-02-01' AS DATE)
