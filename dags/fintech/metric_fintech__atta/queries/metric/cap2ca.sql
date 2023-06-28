WITH base AS (SELECT
      DATE_TRUNC('day',ts_credit_started) AS dt_credit_started,
      COUNT(DISTINCT sk_proposal)         AS cap_proposals,
      SUM(CASE WHEN ts_min_credit_application_approval IS NOT NULL THEN 1 ELSE 0 END) AS cap2ca_proposals
FROM
      dw_atta.fact_pre_analysis_proposal_flow
WHERE ts_credit_started IS NOT NULL
GROUP BY 1)

SELECT
  dt_credit_started,
  ROUND((cap2ca_proposals / cap_proposals), 2) AS cap2ca
FROM
  base
