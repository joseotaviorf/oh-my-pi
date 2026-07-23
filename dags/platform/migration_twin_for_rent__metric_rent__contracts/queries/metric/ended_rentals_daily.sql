SELECT
  dc.dt_annulment AS day,
  country_code,
  COUNT(DISTINCT dc.sk_contract) AS ended_rentals
FROM
  dw_rent.dim_contract AS dc
WHERE
  dc.status = 'Finalizado'
  AND dc.dt_annulment < CURRENT_DATE()
GROUP BY 1, 2
