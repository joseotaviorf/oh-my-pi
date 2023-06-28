WITH base AS (SELECT
      DATE_TRUNC('day',ts_min_credit_application_approval) AS dt_credit_application_approval,
      COUNT(DISTINCT sk_proposal)         AS ca_proposals,
      SUM(CASE WHEN ts_min_inspection IS NOT NULL THEN 1 ELSE 0 END) AS ca2ip_proposals
FROM
      dw_atta.fact_pre_analysis_proposal_flow
WHERE ts_min_credit_application_approval IS NOT NULL
GROUP BY 1)

SELECT
  dt_credit_application_approval,
  ROUND((ca2ip_proposals / ca_proposals), 2) AS ca2ip
FROM
  base
