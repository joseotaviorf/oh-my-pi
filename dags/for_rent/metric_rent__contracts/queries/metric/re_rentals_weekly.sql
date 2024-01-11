WITH ordered_rentals AS (
  SELECT
    COALESCE(dc.dt_start, dc.dt_entrance) AS rental_date,
    dc.sk_contract,
    dc.country_code
  FROM
    dw_rent.dim_contract AS dc
  JOIN
    dw_rent.fact_house_listings AS fhl
      on dc.sk_contract = fhl.sk_contract
  JOIN
    dw_rent.dim_house_listing AS dhl
      on dhl.sk_house_listing = fhl.sk_house_listing
  WHERE
    DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < CURRENT_DATE() -- we know we may have future dates for dt_start
    AND dc.status IN ('Ativo', 'Finalizado')
    AND fhl.nr_renting > 1
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY dhl.id_house ORDER BY fhl.sk_house_listing) > 1
)
SELECT
  DATE_TRUNC('week', ord.rental_date) AS week,
  country_code,
  COUNT(DISTINCT ord.sk_contract) AS re_rentals
FROM
  ordered_rentals AS ord
WHERE
  DATE_TRUNC('week', ord.rental_date) < DATE_TRUNC('week', CURRENT_DATE())
GROUP BY 1, 2
