SELECT
  DATE_TRUNC('week', dc.dt_annulment) AS week,
  dc.country_code,
  COUNT(DISTINCT dc.sk_contract) AS ended_rentals
FROM
  dw_rent.dim_contract AS dc
WHERE
  dc.status = 'Finalizado'
  AND DATE_TRUNC('week',dc.dt_annulment) < DATE_TRUNC('week',current_date)
GROUP BY 1, 2
