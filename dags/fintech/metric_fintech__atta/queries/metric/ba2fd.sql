WITH base AS (SELECT
      DATE_TRUNC('day',ts_min_bank_application) AS dt_bank_application,
      COUNT(DISTINCT sk_proposal)         AS ba_proposals,
      SUM(CASE WHEN ts_financing_ended IS NOT NULL THEN 1 ELSE 0 END) AS ba2fd_proposals
FROM
      dw_atta.fact_pre_analysis_proposal_flow
WHERE ts_min_bank_application IS NOT NULL
GROUP BY 1)

SELECT
  dt_bank_application,
  ROUND((ba2fd_proposals / ba_proposals), 2) AS ba2fd
FROM
  base
