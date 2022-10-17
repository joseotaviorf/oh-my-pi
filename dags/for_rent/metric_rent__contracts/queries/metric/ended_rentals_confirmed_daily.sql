SELECT
	DATE_TRUNC('day',date(COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment))) AS day,
	COUNT(DISTINCT dc.sk_contract) AS ended_rentals_confirmed
FROM 
    dw_public.dim_contract AS dc
WHERE 
    dc.status = 'Finalizado'
    AND COALESCE(ts_analyst_annulment_input, dc.dt_annulment) < CURRENT_DATE
GROUP BY 1