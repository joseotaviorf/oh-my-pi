WITH
dataset_aux AS (
    SELECT DISTINCT
        nps.sk_nps_answer,
        nps.score_category,
        DATE_TRUNC('month', DATE(nps.ts_answered)) AS month_answers,
        dc.value_segment AS category
    FROM 
        dw_retention.fact_contract_termination AS fct
    JOIN
        dw_retention.dim_nps_answer AS nps
            ON nps.sk_nps_answer = fct.sk_nps_answer_owner
    LEFT JOIN 
        dw_rent.dim_contract AS dc
            ON fct.sk_contract = dc.sk_contract
    WHERE
        DATE(nps.ts_answered) >= DATE('2023-01-01')
        AND DATE(nps.ts_answered) < ADD_MONTHS(CURRENT_DATE, 1)
        AND nps.nps_campaign LIKE '%offboarding%' 
        AND DATE(nps.ts_answered) >= DATE_TRUNC('month', DATE(nps.ts_answered)) 
),
dataset_final AS (
    SELECT 
        month_answers,
        category,
        COUNT_IF(score_category = 'promoter') AS promoters,
        COUNT_IF(score_category = 'detractor') AS detractors,
        COUNT(1) AS total_answers
    FROM 
        dataset_aux
    GROUP BY 1,2

    UNION
    
    SELECT 
        month_answers,
        'OVERALL' AS category,
        COUNT_IF(score_category = 'promoter') AS promoters,
        COUNT_IF(score_category = 'detractor') AS detractors,
        COUNT(1) AS total_answers
    FROM 
        dataset_aux
    GROUP BY 1,2
)
SELECT 
    month_answers,
    category,
    promoters,
    detractors,
    total_answers,
    CAST((SUM(promoters) - SUM(detractors))*100 AS DOUBLE)/ SUM(total_answers) * 1.0 AS nps
FROM 
    dataset_final
GROUP BY 1,2,3,4,5