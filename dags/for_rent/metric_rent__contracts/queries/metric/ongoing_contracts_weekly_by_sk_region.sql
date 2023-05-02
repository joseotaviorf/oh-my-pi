SELECT
  dd.week_start,
  hl.sk_region,
  dc.country_code,
  COUNT(DISTINCT dc.sk_contract) AS ongoing_contracts
FROM 
  dw_public.dim_contract AS dc
JOIN 
  dw_public.dim_date AS dd
    ON dd.date BETWEEN DATE(COALESCE(COALESCE(dc.ts_signature, dc.dt_start), dc.dt_entrance)) AND (COALESCE(dc.dt_annulment, CURRENT_DATE()) - 1)
LEFT JOIN 
  dw_public.fact_house_listings AS hl
    ON dc.sk_contract = hl.sk_contract
WHERE 
  dd.date < CURRENT_DATE() -- we know we may have future dates for dt_annulment and we need to filter future dates
  AND dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active and ended
  AND type <> 'DealOnly' -- this type of contract should only be considered for new contracts signed
  and dd.weekday_name = 'Sunday'
GROUP BY 1, 2, 3