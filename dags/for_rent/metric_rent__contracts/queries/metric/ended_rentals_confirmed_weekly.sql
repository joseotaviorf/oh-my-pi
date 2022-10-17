SELECT
	DATE_TRUNC('week',DATE(COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment))) AS week,
	COUNT(DISTINCT dc.sk_contract) AS ended_rentals_confirmed
FROM 
    dw_public.dim_contract dc
WHERE 
    dc.status = 'Finalizado'
    AND DATE_TRUNC('week',DATE(COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment))) < DATE_TRUNC('week',CURRENT_DATE)
GROUP BY 1