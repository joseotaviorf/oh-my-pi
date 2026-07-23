WITH ordered_rentals AS (
  SELECT
    sk_contract,
    sk_region,
    country_code,
    rental_date
  FROM (
    SELECT
      dc.sk_contract,
      fhl.sk_region,
      dc.country_code,
      COALESCE(dc.dt_start, dc.dt_entrance) AS rental_date,
      ROW_NUMBER() OVER (PARTITION BY dhl.id_house ORDER BY fhl.sk_house_listing) AS _w,
      dhl.id_house,
      fhl.sk_house_listing
    FROM dw_rent.dim_contract AS dc
    JOIN dw_rent.fact_house_listings AS fhl
      ON dc.sk_contract = fhl.sk_contract
    JOIN dw_rent.dim_house_listing AS dhl
      ON dhl.sk_house_listing = fhl.sk_house_listing
    WHERE
      CAST(COALESCE(dc.dt_start, dc.dt_entrance) AS DATE) < CURRENT_DATE /* we know we may have future dates for dt_start */
      AND dc.status IN ('Ativo', 'Finalizado')
      AND fhl.nr_renting > 1
  ) AS _t
  WHERE
    _w > 1
)
SELECT
  ord.rental_date,
  ord.sk_region,
  country_code,
  COUNT(DISTINCT ord.sk_contract) AS re_rentals
FROM ordered_rentals AS ord
WHERE
  ord.rental_date < CURRENT_DATE
GROUP BY
  1,
  2,
  3
