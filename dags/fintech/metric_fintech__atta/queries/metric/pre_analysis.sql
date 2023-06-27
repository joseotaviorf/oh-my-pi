SELECT
    date_trunc('day',ts_registration) AS dt_pre_analysis,
    COUNT(DISTINCT sk_offer) AS offer,
    COUNT(DISTINCT sk_pre_analysis) AS pre_analysis

FROM
  dw_atta.fact_pre_analysis_proposal_flow
WHERE ts_registration IS NOT NULL
GROUP BY 1
