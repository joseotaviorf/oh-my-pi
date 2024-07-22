WITH
dataset_aux AS (
    SELECT DISTINCT
        nps.sk_nps_answer,
        nps.score_category,
        dc.country_code,
        CAST(DATE_TRUNC('WEEK', DATE(nps.ts_answered)) AS DATE) AS week_answers,
        dc.value_segment AS category
    FROM 
        dw_retention.fact_nps AS fct_nps
    JOIN 
        dw_retention.fact_contract_termination AS fct_termination
            ON fct_termination.sk_termination = fct_nps.sk_termination
    JOIN
        dw_retention.dim_nps_answer AS nps
            ON nps.sk_nps_answer = fct_nps.sk_nps_answer
    JOIN 
        dw_rent.dim_contract AS dc
            ON fct_termination.sk_contract = dc.sk_contract
    WHERE
        nps.customer_type = 'PP'
        AND DATE(nps.ts_answered) >= DATE('2023-01-01')
        AND DATE(nps.ts_answered) < ADD_MONTHS(CURRENT_DATE, 1)
        AND nps.nps_campaign LIKE '%offboarding%' 
        AND DATE(nps.ts_answered) >= DATE_TRUNC('WEEK', DATE(nps.ts_answered)) 
),
dataset_final AS (
    SELECT 
        week_answers,
        category,
        country_code,
        COUNT_IF(score_category = 'promoter') AS promoters,
        COUNT_IF(score_category = 'detractor') AS detractors,
        COUNT(1) AS total_answers
    FROM 
        dataset_aux
    GROUP BY 
        1, 2, 3

    UNION
    
    SELECT 
        week_answers,
        'OVERALL' AS category,
        country_code,
        COUNT_IF(score_category = 'promoter') AS promoters,
        COUNT_IF(score_category = 'detractor') AS detractors,
        COUNT(1) AS total_answers
    FROM 
        dataset_aux
    GROUP BY 
        1, 2, 3
)
SELECT 
    week_answers,
    category,
    country_code,
    promoters,
    detractors,
    total_answers,
    CAST((SUM(promoters) - SUM(detractors))*100 AS DOUBLE)/ SUM(total_answers) * 1.0 AS nps
FROM 
    dataset_final
GROUP BY 
    1, 2, 3, 4, 5, 6