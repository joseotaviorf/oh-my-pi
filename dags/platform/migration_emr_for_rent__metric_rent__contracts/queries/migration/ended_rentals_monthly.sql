SELECT
  DATE_TRUNC('month', dc.dt_annulment) AS month,
  dc.country_code,
  COUNT(DISTINCT dc.sk_contract) AS ended_rentals
FROM
  dw_rent.dim_contract AS dc
WHERE
  dc.status = 'Finalizado'
  AND DATE_TRUNC('month',dc.dt_annulment) < DATE_TRUNC('month',current_date)
GROUP BY 1, 2
