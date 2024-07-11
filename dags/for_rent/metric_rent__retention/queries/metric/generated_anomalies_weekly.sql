WITH calculations AS (
  SELECT
    DATE(DATE_TRUNC('WEEK', DATE_ADD(dt.dt_termination, 30))) AS dt_termination_expected_finish_week,
    dc.country_code,
    dc.value_segment AS category,
    COUNT(fct.sk_contract) AS terminations,
    COUNT_IF(dc.is_anomaly) AS terminations_with_anomalies
  FROM
    dw_retention.fact_contract_termination AS fct  
  JOIN
    dw_rent.dim_contract AS dc
      ON fct.sk_contract = dc.sk_contract
  JOIN
    dw_retention.dim_termination AS dt
      ON fct.sk_termination = dt.sk_termination
  WHERE
    dt.status <> 'CANCELED'
    AND DATE_ADD(dt.dt_termination, 30) >= DATE('2022-09-01')
    AND DATE_ADD(dt.dt_termination, 30) < CURRENT_DATE()
  GROUP BY
    1, 2, 3
)

SELECT
  dt_termination_expected_finish_week,
  country_code,
  category,
  terminations,
  terminations_with_anomalies,
  terminations_with_anomalies / terminations AS pct_generated_anomalies
FROM
  calculations
UNION ALL
SELECT
  dt_termination_expected_finish_week,
  country_code,
  'OVERALL' AS category,
  SUM(terminations) AS terminations,
  SUM(terminations_with_anomalies) AS terminations_with_anomalies,
  SUM(terminations_with_anomalies) / SUM(terminations) AS pct_generated_anomalies
FROM
  calculations
GROUP BY
  1, 2