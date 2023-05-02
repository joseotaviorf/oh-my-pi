SELECT
  dd.month_start,
  hl.sk_region,
  dc.country_code,
  COUNT(DISTINCT dc.sk_contract) AS ongoing_rentals
FROM 
  dw_public.dim_contract AS dc
JOIN
  dw_public.dim_date AS dd
    ON dd.date BETWEEN DATE(COALESCE(dc.dt_start, dc.dt_entrance)) AND (DATE_ADD(COALESCE(dc.dt_annulment, CURRENT_DATE()), -1))
LEFT JOIN
  dw_public.fact_house_listings AS hl
    ON dc.sk_contract = hl.sk_contract
WHERE 
  dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  AND DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < CURRENT_DATE() -- we know we may have future dates for dt_start
  AND dd.date < CURRENT_DATE() -- we know we may have future dates for dt_annulment and we need to filter future dates
  AND type <> 'DealOnly'
  AND dd.date = dd.month_end 
GROUP BY 1, 2, 3