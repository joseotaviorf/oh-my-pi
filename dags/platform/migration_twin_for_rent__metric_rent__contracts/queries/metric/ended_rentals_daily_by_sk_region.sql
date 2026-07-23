SELECT
  dc.dt_annulment AS contract_annulment_date,
  COALESCE(hl.sk_region, -1) AS sk_region,
  dc.country_code,
  COUNT(DISTINCT dc.sk_contract) AS ended_rentals
FROM
  dw_rent.dim_contract AS dc
LEFT JOIN
  dw_rent.fact_house_listings AS hl
    ON dc.sk_contract = hl.sk_contract
WHERE
  dc.status = 'Finalizado'
  AND dc.dt_annulment < CURRENT_DATE()
GROUP BY 1, 2, 3
