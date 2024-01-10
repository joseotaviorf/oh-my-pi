SELECT
  dd.date AS day,
  dc.country_code,
  COUNT(DISTINCT dc.sk_contract) AS ongoing_rentals
FROM
  dw_rent.dim_contract AS dc
JOIN
  dw_public.dim_date AS dd
    ON dd.date BETWEEN DATE(COALESCE(dc.dt_start, dc.dt_entrance)) AND (DATE_ADD(COALESCE(dc.dt_annulment, CURRENT_DATE()), -1))
LEFT JOIN
  dw_public.fact_house_listings AS fhl
    ON fhl.sk_contract = dc.sk_contract
JOIN
  datalake_pro_owners.daily_owner_houses_quantity_history AS doh
    ON doh.id_owner = fhl.sk_owner AND dd.date = dt_houses_owned
WHERE
  dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  AND DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < CURRENT_DATE() -- we know we may have future dates for dt_start
  AND dd.date < CURRENT_DATE() -- we know we may have future dates for dt_annulment and we need to filter future dates
  AND type <> 'DealOnly'
  AND doh.ongoing_houses >= 5
GROUP BY 1, 2
