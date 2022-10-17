SELECT
  DATE_TRUNC('day',COALESCE(dc.dt_start, dc.dt_entrance)) AS day,
  COUNT(DISTINCT dc.sk_contract) AS new_rentals
FROM 
    dw_public.dim_contract AS dc
WHERE 
    dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active OR were active at a given period
    AND DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
    AND (DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < dc.dt_annulment 
        OR dc.dt_annulment IS NULL) -- consider only contracts that weren't annulled before start DATE
GROUP BY 1