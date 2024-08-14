SELECT
    ts_financing_ended,
    COUNT(DISTINCT sk_offer) AS offer,
    COUNT(DISTINCT sk_pre_analysis) AS pre_analysis,
    COUNT(DISTINCT sk_proposal) AS proposals
FROM
  dw_atta.fact_pre_analysis_proposal_flow
WHERE
    ts_financing_ended IS NOT NULL
GROUP BY
    1
