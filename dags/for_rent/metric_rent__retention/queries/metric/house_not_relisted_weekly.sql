SELECT 
    CAST(DATE_TRUNC('WEEK', DATE(dt.ts_created)) AS DATE) AS dt_week_tr,
    fct.country_code,
    'OVERALL' AS category,
    COUNT(DISTINCT fct.sk_contract) AS qtd_tr,
    COUNT(DISTINCT 
        IF(dt.requested_by = 'LANDLORD', fct.sk_contract, NULL)
    ) AS qtd_tr_requested_by_pp,
    CAST(COUNT(DISTINCT IF(dt.requested_by = 'LANDLORD', fct.sk_contract, NULL)) AS DOUBLE) / COUNT(DISTINCT fct.sk_contract) AS pct_tr_requested_by_pp
FROM
    dw_retention.fact_contract_termination AS fct
JOIN
    dw_retention.dim_termination AS dt 
        ON dt.sk_termination = fct.sk_termination
JOIN 
    dw_rent.dim_contract AS dc 
        ON fct.sk_contract = dc.sk_contract
WHERE 
    dt.status <> 'CANCELED'
    AND DATE_TRUNC('WEEK', dt.ts_created) <= DATE_TRUNC('WEEK', CURRENT_DATE)
GROUP BY 
    1 , 2, 3

UNION ALL

SELECT 
    CAST(DATE_TRUNC('WEEK', DATE(dt.ts_created)) AS DATE) AS dt_week_tr,
    fct.country_code,
    dc.value_segment AS category,
    COUNT(DISTINCT fct.sk_contract) AS qtd_tr,
    COUNT(DISTINCT 
        IF(dt.requested_by = 'LANDLORD', fct.sk_contract, NULL)
    ) AS qtd_tr_requested_by_pp,
    CAST(COUNT(DISTINCT IF(dt.requested_by = 'LANDLORD', fct.sk_contract, NULL)) AS DOUBLE) / COUNT(DISTINCT fct.sk_contract) AS pct_tr_requested_by_pp
FROM
    dw_retention.fact_contract_termination AS fct
JOIN
    dw_retention.dim_termination AS dt 
        ON dt.sk_termination = fct.sk_termination
JOIN 
    dw_rent.dim_contract AS dc 
        ON fct.sk_contract = dc.sk_contract
WHERE 
    dt.status <> 'CANCELED'
    AND DATE_TRUNC('WEEK', dt.ts_created) <= DATE_TRUNC('WEEK', CURRENT_DATE)
GROUP BY 
    1 , 2, 3