SELECT 
  CAST(DATE_TRUNC('WEEK', dt.ts_termination_finished) AS DATE) AS dt_week_termination_finished,
  dc.country_code,
  'OVERALL' AS category,
  'OVERALL' AS repair_resolution_class,
  COUNT(DISTINCT fct.sk_termination) AS total_terminations,
  CAST(AVG(DATEDIFF(dt.ts_termination_finished, dt.dt_termination)) AS NUMERIC(5,2)) AS leadtime_offboarding
FROM 
  dw_retention.fact_contract_termination AS fct
JOIN
  dw_retention.dim_termination AS dt
    ON dt.sk_termination = fct.sk_termination
JOIN
  dw_rent.dim_contract AS dc
    ON dc.sk_contract = fct.sk_contract
GROUP BY 
  1, 2, 3, 4

UNION ALL

SELECT 
  CAST(DATE_TRUNC('WEEK', dt.ts_termination_finished) AS DATE) AS dt_week_termination_finished,
  dc.country_code,
  'OVERALL' AS category,
  CASE 
    WHEN dt.repair_resolution IS NULL OR dt.repair_resolution IN ('NO_REPAIR_NEEDED', 'FORGIVEN_BY_LANDLORD') THEN 'without_repair'
    ELSE 'with_repair'
  END AS repair_resolution_class,
  COUNT(DISTINCT fct.sk_termination) AS total_terminations,
  CAST(AVG(DATEDIFF(dt.ts_termination_finished, dt.dt_termination)) AS NUMERIC(5,2)) AS leadtime_offboarding
FROM 
  dw_retention.fact_contract_termination AS fct
JOIN
  dw_retention.dim_termination AS dt
    ON dt.sk_termination = fct.sk_termination
JOIN
  dw_rent.dim_contract AS dc
    ON dc.sk_contract = fct.sk_contract
GROUP BY 
  1, 2, 3, 4

UNION ALL

SELECT 
  CAST(DATE_TRUNC('WEEK', dt.ts_termination_finished) AS DATE) AS dt_week_termination_finished,
  dc.country_code,
  dc.value_segment AS category,
  CASE 
    WHEN dt.repair_resolution IS NULL OR dt.repair_resolution IN ('NO_REPAIR_NEEDED', 'FORGIVEN_BY_LANDLORD') THEN 'without_repair'
    ELSE 'with_repair'
  END AS repair_resolution_class,
  COUNT(DISTINCT fct.sk_termination) AS total_terminations,
  CAST(AVG(DATEDIFF(dt.ts_termination_finished, dt.dt_termination)) AS NUMERIC(5,2)) AS leadtime_offboarding
FROM 
  dw_retention.fact_contract_termination AS fct
JOIN
  dw_retention.dim_termination AS dt
    ON dt.sk_termination = fct.sk_termination
JOIN
  dw_rent.dim_contract AS dc
    ON dc.sk_contract = fct.sk_contract
GROUP BY 
  1, 2, 3, 4

UNION ALL

SELECT 
  CAST(DATE_TRUNC('WEEK', dt.ts_termination_finished) AS DATE) AS dt_week_termination_finished,
  dc.country_code,
  dc.value_segment AS category,
  'OVERALL' AS repair_resolution_class,
  COUNT(DISTINCT fct.sk_termination) AS total_terminations,
  CAST(AVG(DATEDIFF(dt.ts_termination_finished, dt.dt_termination)) AS NUMERIC(5,2)) AS leadtime_offboarding
FROM 
  dw_retention.fact_contract_termination AS fct
JOIN
  dw_retention.dim_termination AS dt
    ON dt.sk_termination = fct.sk_termination
JOIN
  dw_rent.dim_contract AS dc
    ON dc.sk_contract = fct.sk_contract
GROUP BY 
  1, 2, 3, 4