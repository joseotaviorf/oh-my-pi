WITH base AS (SELECT
      DATE_TRUNC('day',ts_min_bank_application) AS ts_financing_ended,
      COUNT(DISTINCT sk_proposal)         AS ba_proposals,
      SUM(CASE WHEN ts_financing_ended IS NOT NULL THEN 1 ELSE 0 END) AS ba2fd_proposals
FROM
      dw_atta.fact_pre_analysis_proposal_flow
WHERE ts_min_bank_application IS NOT NULL
GROUP BY 1)

SELECT
  dt_bank_application,
  ROUND((ba_proposals / ba2fd_proposals), 2) AS ba2fd
FROM
  base
