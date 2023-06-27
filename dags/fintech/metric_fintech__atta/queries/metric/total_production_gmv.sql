SELECT
    f.ts_financing_ended    AS dt_financing_ended,
    SUM(p.financing_value)  AS gmv
FROM
  dw_atta.fact_pre_analysis_proposal_flow f
LEFT JOIN
  dw_atta.dim_proposal_atta p ON p.sk_proposal = f.sk_proposal
WHERE
  f.ts_financing_ended IS NOT NULL
GROUP BY 1
