SELECT
  DATE_TRUNC('month', dc.dt_annulment) AS month,
  dc.country_code,
  COUNT(DISTINCT dc.sk_contract) AS ended_rentals
FROM
  dw_rent.dim_contract AS dc
LEFT JOIN
  dw_rent.fact_house_listings AS fhl
    ON fhl.sk_contract = dc.sk_contract
JOIN
  datalake_pro_owners.daily_owner_houses_quantity_history AS doh
    ON doh.id_owner = fhl.sk_owner AND dc.dt_annulment = dt_houses_owned
WHERE
  dc.status = 'Finalizado'
  AND DATE_TRUNC('month',dc.dt_annulment) < DATE_TRUNC('month',current_date)
  AND doh.ongoing_houses >= 5
GROUP BY 1, 2
