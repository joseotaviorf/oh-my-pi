SELECT
    date_trunc('month', CAST(dna.ts_answered AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS detractors,
    COUNT(DISTINCT dna.sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT dna.sk_nps_answer) * 100, 1
    ) AS nps_offboarding
FROM dw_customer_satisfaction.fact_nps_dispatches AS fnd
INNER JOIN dw_customer_satisfaction.dim_nps_answer AS dna
    ON fnd.sk_nps_answer = dna.sk_nps_answer
INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc
    ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
WHERE fnd.is_answered = true
  AND dnc.business_context = 'forRent'
  AND dnc.customer_journey = 'true'
  AND dnc.purpose = 'main'
  AND dnc.metric_group IN ('iqoffboarding', 'ppoffboarding')
  AND CAST(dna.ts_answered AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(dna.ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
