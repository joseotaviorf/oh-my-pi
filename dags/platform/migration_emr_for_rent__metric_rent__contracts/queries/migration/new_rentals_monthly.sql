SELECT
  DATE_TRUNC('month',COALESCE(dc.dt_start, dc.dt_entrance)) AS month,
  dc.country_code,
  COUNT(DISTINCT dc.sk_contract) AS new_rentals
FROM
    dw_rent.dim_contract dc
WHERE
    dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
    AND DATE_TRUNC('month',COALESCE(dc.dt_start, dc.dt_entrance)) < DATE_TRUNC('month',current_date) -- we know we may have future dates for dt_start
    AND (DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < dc.dt_annulment
        OR dc.dt_annulment IS NULL) -- consider only contracts that weren't annulled before start DATE
GROUP BY 1, 2
