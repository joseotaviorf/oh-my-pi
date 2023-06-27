SELECT
    date_trunc('day',ts_min_bank_application) AS dt_bank_application,
    COUNT(DISTINCT sk_offer) AS offer,
    COUNT(DISTINCT sk_pre_analysis) AS pre_analysis,
    COUNT(DISTINCT sk_proposal) AS proposals

FROM
  dw_atta.fact_pre_analysis_proposal_flow
WHERE ts_min_bank_application IS NOT NULL
GROUP BY 1
