WITH base AS (SELECT
      DATE_TRUNC('day',ts_min_inspection) AS dt_inspection,
      COUNT(DISTINCT sk_proposal)         AS ip_proposals,
      SUM(CASE WHEN ts_min_checklist IS NOT NULL THEN 1 ELSE 0 END) AS ip2cl_proposals
FROM
      dw_atta.fact_pre_analysis_proposal_flow
WHERE ts_min_inspection IS NOT NULL
GROUP BY 1)

SELECT
  dt_inspection,
  ROUND((ip_proposals / ip2cl_proposals), 2) AS ip2cl
FROM
  base
