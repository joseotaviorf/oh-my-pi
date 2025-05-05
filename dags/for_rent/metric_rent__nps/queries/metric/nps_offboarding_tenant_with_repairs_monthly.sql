SELECT
  dd_answer.month_start AS dt_month_answered,
  dc.value_segment AS category,
  dc.country_code,
  COUNT(fnd.sk_nps_answer) AS total_answers_repairs_needed,
  COUNT(IF(fnd.score < 7, fnd.sk_nps_answer, NULL)) AS detractors_repairs_needed,
  COUNT(IF(fnd.score > 8, fnd.sk_nps_answer, NULL)) AS promoters_repairs_needed,
  COUNT(IF(fnd.score between 7 and 8, fnd.sk_nps_answer, NULL)) AS neutrals_repairs_needed,
  100 * (COUNT(IF(fnd.score > 8, sk_nps_answer, NULL)) - COUNT(IF(fnd.score < 7, sk_nps_answer, NULL))) / COUNT(sk_nps_answer) AS nps_repairs_needed
FROM
  dw_customer_satisfaction.fact_nps_dispatches AS fnd
JOIN
  dw_customer_satisfaction.dim_nps_campaign AS dnc
    ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
JOIN
  dw_rent.dim_contract AS dc
    ON fnd.sk_contract = dc.sk_contract
JOIN
  dw_public.dim_date AS dd_answer
    ON fnd.sk_answered_date = dd_answer.sk_date
WHERE
  dd_answer.year >= 2022
  AND fnd.sk_nps_answer > 0
  AND dnc.business_context = 'forRent'
  AND dnc.metric_group = 'iqoffboarding'
  AND dnc.customer_type = 'IQ'
  AND dc.is_repair_tenant_duty = TRUE
GROUP BY
  1, 2, 3

UNION ALL

SELECT
  dd_answer.month_start AS dt_month_answered,
  'OVERALL' AS category,
  dc.country_code,
  COUNT(fnd.sk_nps_answer) AS total_answers_repairs_needed,
  COUNT(IF(fnd.score < 7, fnd.sk_nps_answer, NULL)) AS detractors_repairs_needed,
  COUNT(IF(fnd.score > 8, fnd.sk_nps_answer, NULL)) AS promoters_repairs_needed,
  COUNT(IF(fnd.score between 7 and 8, fnd.sk_nps_answer, NULL)) AS neutrals_repairs_needed,
  100 * (COUNT(IF(fnd.score > 8, sk_nps_answer, NULL)) - COUNT(IF(fnd.score < 7, sk_nps_answer, NULL))) / COUNT(sk_nps_answer) AS nps_repairs_needed
FROM
  dw_customer_satisfaction.fact_nps_dispatches AS fnd
JOIN
  dw_customer_satisfaction.dim_nps_campaign AS dnc
    ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
JOIN
  dw_rent.dim_contract AS dc
    ON fnd.sk_contract = dc.sk_contract
JOIN
  dw_public.dim_date AS dd_answer
    ON fnd.sk_answered_date = dd_answer.sk_date
WHERE
  dd_answer.year >= 2022
  AND fnd.sk_nps_answer > 0
  AND dnc.business_context = 'forRent'
  AND dnc.metric_group = 'iqoffboarding'
  AND dnc.customer_type = 'IQ'
  AND dc.is_repair_tenant_duty = TRUE
GROUP BY
  1, 2, 3