SELECT
  DATE_TRUNC('day',COALESCE(dc.dt_start, dc.dt_entrance)) AS day,
  dc.country_code,
  COUNT(DISTINCT dc.sk_contract) AS new_rentals
FROM 
    dw_public.dim_contract AS dc
JOIN
    dw_public.fact_house_listings AS fhl
      ON dc.sk_contract = fhl.sk_contract
JOIN
    datalake_pro_owners.daily_owner_houses_quantity_history AS doh
      ON doh.id_owner = fhl.sk_owner
        AND coalesce(dc.dt_start, dc.dt_entrance) = doh.dt_houses_owned
WHERE 
    dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active OR were active at a given period
    AND doh.ongoing_houses >= 5
    AND DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
    AND (DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < dc.dt_annulment 
        OR dc.dt_annulment IS NULL) -- consider only contracts that weren't annulled before start DATE
GROUP BY 1, 2