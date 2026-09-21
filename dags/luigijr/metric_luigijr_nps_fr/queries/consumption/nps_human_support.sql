WITH seamless_base AS (
    SELECT sk_nps_answer, score_category, seamless_ticket_type, data_resposta_nps
    FROM sandbox.nps_onb_cohort
    UNION ALL
    SELECT sk_nps_answer, score_category, seamless_ticket_type, data_resposta_nps
    FROM sandbox.nps_ong_cohort
)
SELECT
    date_trunc('month', CAST(data_resposta_nps AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS detractors,
    COUNT(DISTINCT sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT sk_nps_answer) * 100, 1
    ) AS nps_human_support
FROM seamless_base
WHERE seamless_ticket_type = 'tickets'
  AND CAST(data_resposta_nps AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(data_resposta_nps AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
