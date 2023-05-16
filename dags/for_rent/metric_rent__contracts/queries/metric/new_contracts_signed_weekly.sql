SELECT
    DATE_TRUNC('week', COALESCE(dc.ts_signature, dc.dt_start)) AS week,
    dc.country_code,
    COUNT(DISTINCT dc.sk_contract) AS new_contracts_signed
FROM 
    dw_public.dim_contract dc
LEFT JOIN 
    dw_public.fact_house_listings hl
        ON dc.sk_contract = hl.sk_contract
WHERE 
    dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active AND ended
    AND DATE_TRUNC('week', DATE(COALESCE(dc.ts_signature, dc.dt_start))) < DATE_TRUNC('week', current_date)
GROUP BY 1, 2