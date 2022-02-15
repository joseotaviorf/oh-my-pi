SELECT   
    ca.id_credit_analysis,
    ca.id_analyst,
    ca.type AS documentation_policy,
    ca.bypass,
    cr.risk_category,
    cr.score AS internal_score,
    cr.liquidity,
    ca.reason,
    ca.result,
    ca.level,
    CASE
        WHEN ca.id_proposal IS NULL THEN 'Error'
        WHEN ca.category IS NULL THEN 'Clear-No'
        WHEN ca.category IN (1,2,3,4,5,6) THEN 'Insurance'
        WHEN ca.category IN (7,8,9,10,11,12,13,14,15,16,17,18,19) THEN 'Insurance or Deposit'
        WHEN ca.category IN (20,21,22,23,24) THEN 'Deposit'
        WHEN (ca.category = 0 OR bypass IS NOT NULL) THEN 'Free'
          ELSE 'Error' 
    END AS credit_decision_cluster,
    IF(id_analyst IS NULL, FALSE, TRUE) AS is_manual_analysis,
    ca.ts_created AS ts_credit_analysis_created,
    NOW() AS ts_load
FROM
    datalake_sorting_hat_clean.credit_analysis AS ca 
LEFT JOIN
    datalake_sorting_hat_clean.screening_result AS cr 
        ON cr.id_proposal = ca.id_proposal