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
    'SALE' AS business_context,
    COALESCE(fls.status_history, 'NA') AS status,
    fl.price,
    fls.ts_status_started
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
      di.id_house_listing,
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
    SUBSTRING(fhls.sk_house_listing,0,9) AS id_house,
    'RENT' AS business_context,
    COALESCE(fhls.status_history, 'NA') AS status,
    di.rent AS price,
    fhls.ts_status_start AS ts_status_started
  FROM
    dw_rent.fact_house_listing_status AS fhls
  LEFT JOIN
    daily_info AS di
      ON fhls.sk_house_listing = di.id_house_listing
),
union_listing AS (
  SELECT
    s.id_house,
    s.business_context,
    s.status,
    s.price,
    s.ts_status_started
  FROM
    sale AS s
  UNION
  SELECT
    r.id_house,
    r.business_context,
    r.status,
    r.price,
    r.ts_status_started
  FROM
    rent AS r
),
status_published AS (
  SELECT
    ul.id_house,
    ul.business_context,
    'PUBLISHED' AS status,
    hist_price.price,
    ul.ts_status_started
  FROM
    union_listing AS ul
  LEFT JOIN
    datalake_atlas_pricing_report.status_history_house_price_change AS hist_price
      ON hist_price.id_house = ul.id_house
        AND hist_price.business_context = ul.business_context
        AND ul.ts_status_started >= hist_price.ts_price_started
        AND ul.ts_status_started <= COALESCE(hist_price.ts_price_ended, CURRENT_DATE)
  WHERE
    ul.status IN ('PUBLISHED','publicado')
),
rent_price_fallback AS (
  SELECT
    sp.id_house,
    sp.business_context,
    sp.status,
    COALESCE(dailyinfo.rent,0) AS price,
    sp.ts_status_started
  FROM
    status_published AS sp
  LEFT JOIN
    datalake_rental_historical_follow_up.house_listings_daily_info AS dailyinfo
      ON dailyinfo.id_house = sp.id_house
        AND dailyinfo.year = YEAR(sp.ts_status_started)
        AND dailyinfo.month = MONTH(sp.ts_status_started)
        AND dailyinfo.day = DAY(sp.ts_status_started)
  WHERE
    sp.price IS NULL
    AND sp.business_context = 'RENT'
),
sale_price_fallback_ranked AS (
  SELECT
    sp.id_house,
    sp.business_context,
    sp.status,
    h_aud.sale_price AS price,
    sp.ts_status_started,
    ROW_NUMBER() OVER(PARTITION BY sp.id_house, sp.ts_status_started ORDER BY FROM_UNIXTIME(r.ts_revision/1000) DESC) AS rn
  FROM
    status_published AS sp
  INNER JOIN
    datalake_ebdb_clean.house_aud AS h_aud
      ON h_aud.id_house = sp.id_house
  INNER JOIN
    datalake_ebdb_clean.user_revision_entity AS r
        ON h_aud.rev = r.id
          AND sp.ts_status_started >= FROM_UNIXTIME(r.ts_revision/1000)
  WHERE
    sp.price IS NULL
    AND sp.business_context = 'SALE'
),
sale_price_fallback AS (
  SELECT
    id_house,
    business_context,
    status,
    price,
    ts_status_started
  FROM
    sale_price_fallback_ranked
  WHERE
    rn = 1
)
SELECT
  sp.id_house,
  sp.business_context,
  sp.status,
  sp.price,
  sp.ts_status_started
FROM
  status_published AS sp
WHERE
  sp.price IS NOT NULL
UNION ALL
SELECT
  rpf.id_house,
  rpf.business_context,
  rpf.status,
  rpf.price,
  rpf.ts_status_started
FROM
  rent_price_fallback AS rpf
UNION ALL
SELECT
  spf.id_house,
  spf.business_context,
  spf.status,
  spf.price,
  spf.ts_status_started
FROM
  sale_price_fallback AS spf
UNION ALL
SELECT
  ul.id_house,
  ul.business_context,
  'UNPUBLISHED' AS status,
  NULL AS price,
  ul.ts_status_started
FROM
  union_listing AS ul
WHERE
  ul.status IN ('despublicado', 'UNPUBLISHED')
