WITH ongoing_listings AS (
  SELECT /*+ RANGE_JOIN(fhls, 800) */
    fhls.sk_house_listing,
    fhls.country_code,
    d.date
  FROM
    dw_rent.fact_house_listing_status AS fhls
  JOIN
    dw_rent.dim_house_listing AS dhl
      ON fhls.sk_house_listing = dhl.sk_house_listing
  JOIN
    dw_public.dim_region AS dr
      ON fhls.sk_region = dr.sk_region
  JOIN
    dw_public.dim_date AS d
      ON d.date BETWEEN COALESCE(DATE(fhls.ts_status_start), DATE('2000-01-01'))
        AND COALESCE(DATE_ADD(DATE(fhls.ts_status_end), -1), CURRENT_DATE())
  WHERE
    fhls.status_history IN ('publicado', 'PUBLISHED') -- consider only published status
    AND dhl.version <> 0 -- consider only listings that already started publication
    AND dr.city_group IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY fhls.sk_house_listing, d.date ORDER BY fhls.ts_status_start DESC) = 1
)

SELECT
  date AS day,
  country_code,
  COUNT(DISTINCT sk_house_listing) AS ongoing_listings
FROM
  ongoing_listings
GROUP BY 1, 2
