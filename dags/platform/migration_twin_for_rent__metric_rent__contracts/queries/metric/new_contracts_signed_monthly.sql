SELECT
    DATE_TRUNC('month', COALESCE(dc.ts_signature, dc.dt_start)) AS month,
    dc.country_code,
    COUNT(DISTINCT dc.sk_contract) AS new_contracts_signed
FROM
    dw_rent.dim_contract AS dc
LEFT JOIN
    dw_rent.fact_house_listings AS hl
        ON dc.sk_contract = hl.sk_contract
WHERE
    dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active and ended
    AND DATE_TRUNC('month', DATE(COALESCE(dc.ts_signature, dc.dt_start))) <= DATE_TRUNC('month', CURRENT_DATE)
    AND DATE(COALESCE(dc.ts_signature, dc.dt_start)) < CURRENT_DATE()
GROUP BY 1, 2
