WITH base AS (SELECT
      DATE_TRUNC('day',ts_min_checklist) AS dt_checklist,
      COUNT(DISTINCT sk_proposal)         AS cl_proposals,
      SUM(CASE WHEN ts_min_bank_application IS NOT NULL THEN 1 ELSE 0 END) AS cl2ba_proposals
FROM
      dw_atta.fact_pre_analysis_proposal_flow
WHERE ts_min_checklist IS NOT NULL
GROUP BY 1)

SELECT
  dt_checklist,
  ROUND((cl_proposals / cl2ba_proposals), 2) AS cl2ba
FROM
  base
