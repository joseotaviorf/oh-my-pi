SELECT
    DATE_TRUNC('day', coalesce(dc.ts_signature, dc.dt_start)) AS day,
    dc.country_code,
    COUNT(DISTINCT dc.sk_contract) AS new_contracts_signed
FROM 
    dw_public.dim_contract dc
LEFT JOIN 
    dw_public.fact_house_listings hl
        ON dc.sk_contract = hl.sk_contract
    WHERE 
        dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active and ended
GROUP BY 1, 2