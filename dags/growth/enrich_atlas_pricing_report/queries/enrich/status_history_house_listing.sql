WITH sale AS (
  WITH aux_fs AS (
    SELECT
      sk_sale_listing,
      MIN(ts_load) AS min_load
    FROM
      dw_sale.fact_listings
    GROUP BY 1
  ),
  first_load AS (
    SELECT
      SUBSTRING(fl.sk_sale_listing,0,9) AS id_house,
      fl.sk_sale_listing AS sk_house_listing,
      fl.price
    FROM
      dw_sale.fact_listings AS fl
    INNER JOIN
      aux_fs AS afs
        ON fl.sk_sale_listing = afs.sk_sale_listing
        AND afs.min_load = fl.ts_load
  )
  SELECT
    SUBSTRING(fls.sk_sale_listing,0,9) AS id_house,
    SUBSTRING(fls.sk_sale_listing,10,12) AS version,
    'SALE' AS business_context,
    fls.status_history AS status,
    COALESCE(fls.status_change_reason, 'NA') AS status_reason,
    fls.ts_status_started,
    fl.price
  FROM
    dw_sale.fact_listing_status AS fls
  INNER JOIN
    first_load AS fl
      ON fls.sk_sale_listing = fl.sk_house_listing
),
rent AS (
  WITH aux_fr AS (
    SELECT
      id_house_listing,
      MIN(dt_day) AS min_day
    FROM
      datalake_rental_historical_follow_up.house_listings_daily_info
    GROUP BY 1
  ),
  daily_info AS (
    SELECT
      di.dt_day,
      di.id_house,
      di.id_house_listing,
      di.listing_category,
      di.rent
    FROM
      datalake_rental_historical_follow_up.house_listings_daily_info AS di
    INNER JOIN
      aux_fr AS a
        ON a.id_house_listing = di.id_house_listing
        AND a.min_day = di.dt_day
    WHERE
      country_code = 'BR'
  )
  SELECT
    SUBSTRING(sk_house_listing,0,9) AS id_house,
    SUBSTRING(sk_house_listing,10,12) AS version,
    'RENT' AS business_context,
    fhls.status_history AS status,
    COALESCE(fhls.status_change_reason, 'NA') AS status_reason,
    fhls.ts_status_start AS ts_status_started,
    di.rent AS price
  FROM
    dw_public.fact_house_listing_status AS fhls
  LEFT JOIN
    daily_info AS di
      ON fhls.sk_house_listing = di.id_house_listing
)
SELECT
  s.id_house,
  s.version,
  s.business_context,
  s.status,
  s.status_reason,
  s.price,
  s.ts_status_started
FROM
  sale AS s
UNION
SELECT
  r.id_house,
  r.version,
  r.business_context,
  r.status,
  r.status_reason,
  r.price,
  r.ts_status_started
FROM
  rent AS r
