SELECT
    COALESCE(dc.dt_start, dc.dt_entrance) AS rental_date,
    COALESCE(hl.sk_region, -1) AS sk_region,
    dc.country_code,
    COUNT(DISTINCT dc.sk_contract) AS new_rentals
FROM
    dw_rent.dim_contract AS dc
LEFT JOIN
    dw_rent.fact_house_listings AS hl
        ON dc.sk_contract = hl.sk_contract
WHERE
    dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
    AND DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
    AND (DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < dc.dt_annulment
        OR dc.dt_annulment IS NULL) -- consider only contracts that weren't annulled before start DATE
GROUP BY 1, 2, 3
