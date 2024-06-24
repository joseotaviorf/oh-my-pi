SELECT
    DATE_TRUNC('week', COALESCE(dc.ts_signature, dc.dt_start)) AS week,
    dc.country_code,
    COUNT(DISTINCT dc.sk_contract) AS new_contracts_signed
FROM
    dw_rent.dim_contract AS dc
LEFT JOIN
    dw_rent.fact_house_listings AS hl
        ON dc.sk_contract = hl.sk_contract
WHERE
    dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active AND ended
    AND DATE_TRUNC('week', DATE(COALESCE(dc.ts_signature, dc.dt_start))) <= DATE_TRUNC('week', CURRENT_DATE())
    AND DATE(COALESCE(dc.ts_signature, dc.dt_start)) < CURRENT_DATE()
GROUP BY 1, 2
