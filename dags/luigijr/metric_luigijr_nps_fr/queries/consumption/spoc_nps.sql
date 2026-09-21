SELECT
    date_trunc('month', CAST(ts_answered AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS detractors,
    COUNT(DISTINCT sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT sk_nps_answer) * 100, 1
    ) AS spoc_nps
FROM sandbox.nps_fr
WHERE campanha_nps = 'offboarding'
  AND is_spoc_test = true
  AND CAST(ts_answered AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
