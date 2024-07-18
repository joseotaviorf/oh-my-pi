SELECT
  DATE(DATE_TRUNC('MONTH', dd_answer.date)) AS dt_month_answered,
  dc.value_segment AS category,
  dc.country_code,
  COUNT(fnd.sk_nps_answer) AS total_answers,
  COUNT(IF(fnd.score < 7, fnd.sk_nps_answer, NULL)) AS detractors,
  COUNT(IF(fnd.score > 8, fnd.sk_nps_answer, NULL)) AS promoters,
  COUNT(IF(fnd.score BETWEEN 7 AND 8, fnd.sk_nps_answer, NULL)) AS neutrals,
  100 * (COUNT(IF(fnd.score > 8, sk_nps_answer, NULL)) - COUNT(IF(fnd.score < 7, sk_nps_answer, NULL))) / COUNT(sk_nps_answer) AS nps
FROM
  dw_tracksale.fact_nps_dispatches AS fnd
JOIN
  dw_tracksale.dim_nps_campaign AS dnc
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
  AND dnc.metric_group IN ('iqoffboarding', 'ppoffboarding')
GROUP BY
  1, 2, 3

UNION ALL

SELECT
  DATE(DATE_TRUNC('MONTH', dd_answer.date)) AS dt_month_answered,
  'OVERALL' AS category,
  dc.country_code,
  COUNT(fnd.sk_nps_answer) AS total_answers,
  COUNT(IF(fnd.score < 7, fnd.sk_nps_answer, NULL)) AS detractors,
  COUNT(IF(fnd.score > 8, fnd.sk_nps_answer, NULL)) AS promoters,
  COUNT(IF(fnd.score BETWEEN 7 AND 8, fnd.sk_nps_answer, NULL)) AS neutrals,
  100 * (COUNT(IF(fnd.score > 8, sk_nps_answer, NULL)) - COUNT(IF(fnd.score < 7, sk_nps_answer, NULL))) / COUNT(sk_nps_answer) AS nps
FROM
  dw_tracksale.fact_nps_dispatches AS fnd
JOIN
  dw_tracksale.dim_nps_campaign AS dnc
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
  AND dnc.metric_group IN ('iqoffboarding', 'ppoffboarding')
GROUP BY
  1, 2, 3