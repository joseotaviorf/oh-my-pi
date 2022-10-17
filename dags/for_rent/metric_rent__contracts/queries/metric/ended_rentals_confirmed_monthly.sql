SELECT
	DATE_TRUNC('month',DATE(COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment))) AS month,
	COUNT(DISTINCT dc.sk_contract) AS ended_rentals_confirmed
FROM 
    dw_public.dim_contract dc
WHERE 
    dc.status = 'Finalizado'
    AND DATE_TRUNC('month',DATE(COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment))) < DATE_TRUNC('month',CURRENT_DATE)
GROUP BY 1