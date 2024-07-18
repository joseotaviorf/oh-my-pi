WITH
dataset_aux AS (
    SELECT DISTINCT
        nps.sk_nps_answer,
        nps.score_category,
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
        AND dc.is_repair_tenant_duty <> TRUE
        AND DATE(nps.ts_answered) >= DATE_TRUNC('WEEK', DATE(nps.ts_answered))
),
dataset_final AS (
    SELECT 
        week_answers,
        category,
        COUNT(CASE
            WHEN
                score_category = 'promoter' THEN 0 
            END) AS promoters_no_repairs_need,
        COUNT( CASE 
            WHEN 
                score_category = 'detractor' THEN 0 
            END) detractors_no_repairs_need,
        COUNT(1) AS total_answers_no_repairs_need
    FROM 
        dataset_aux
    GROUP BY 
        1, 2

    UNION
    
    SELECT 
        week_answers,
        'OVERALL' AS category,
        COUNT(CASE
            WHEN
                score_category = 'promoter' THEN 0 
            END) AS promoters_no_repairs_need,
        COUNT( CASE 
            WHEN 
                score_category = 'detractor' THEN 0 
            END) detractors_no_repairs_need,
        COUNT(1) AS total_answers_no_repairs_need
    FROM 
        dataset_aux
    GROUP BY 
        1, 2
)
SELECT 
    week_answers,
    category,
    promoters_no_repairs_need,
    detractors_no_repairs_need,
    total_answers_no_repairs_need,
    CAST((SUM(promoters_no_repairs_need) - SUM(detractors_no_repairs_need))*100 AS DOUBLE)/ SUM(total_answers_no_repairs_need) * 1.0 AS nps_no_repairs_needs
FROM 
    dataset_final
GROUP BY 
    1, 2, 3, 4, 5