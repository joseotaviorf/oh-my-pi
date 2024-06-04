WITH ongoing_listings AS (
  SELECT
    month_start,
    sk_region,
    ongoing_listings
  FROM metric_rent.ongoing_listings_monthly_by_sk_region
), new_rentals_monthly AS (
  SELECT
    DATE_TRUNC('MONTH', rental_date) AS month_start,
    sk_region,
    SUM(new_rentals) AS new_rentals
  FROM metric_rent.new_rentals_daily_by_sk_region
  GROUP BY
    1,
    2
), new_contracts_signed AS (
  SELECT
    DATE_TRUNC('MONTH', contract_signed_date) AS month_start,
    sk_region,
    SUM(new_contracts_signed) AS new_contracts_signed
  FROM metric_rent.new_contracts_signed_daily_by_sk_region
  GROUP BY
    1,
    2
), ongoing_rentals AS (
  SELECT
    month_start,
    sk_region,
    ongoing_rentals
  FROM metric_rent.ongoing_rentals_monthly_by_sk_region
), new_listings AS (
  SELECT
    DATE_TRUNC('MONTH', hl.ts_listing_version_start) AS dt_month_start,
    fh.sk_region,
    hl.listing_category_start,
    CAST(NULL AS INT) AS ongoing_listings,
    CAST(NULL AS INT) AS new_rentals,
    CAST(NULL AS INT) AS new_contracts_signed,
    CAST(NULL AS INT) AS ongoing_rentals,
    COUNT(DISTINCT hl.sk_house_listing) AS new_listings
  FROM dw_rent.dim_house_listing AS hl
  LEFT JOIN dw_rent.fact_house_listings AS fh
    ON fh.sk_house_listing = hl.sk_house_listing
  WHERE
    NOT ts_listing_version_start IS NULL
    AND sk_region > 0
    AND hl.is_for_rent = TRUE
    AND DATE_TRUNC('MONTH', hl.ts_listing_version_start) >= DATE('2018-01-01')
  GROUP BY
    1,
    2,
    3
), full_join AS (
  SELECT
    COALESCE(ol.month_start, nr.month_start, cs.month_start, orm.month_start) AS dt_month_start,
    COALESCE(ol.sk_region, nr.sk_region, cs.sk_region, orm.sk_region) AS sk_region,
    CAST(NULL AS STRING) AS listing_category_start,
    ongoing_listings,
    new_rentals,
    new_contracts_signed,
    ongoing_rentals,
    CAST(NULL AS INT) AS new_listings
  FROM ongoing_listings AS ol
  FULL OUTER JOIN new_rentals_monthly AS nr
    ON ol.month_start = nr.month_start AND ol.sk_region = nr.sk_region
  FULL OUTER JOIN new_contracts_signed AS cs
    ON ol.month_start = cs.month_start AND ol.sk_region = cs.sk_region
  FULL OUTER JOIN ongoing_rentals AS orm
    ON ol.month_start = orm.month_start AND ol.sk_region = orm.sk_region
  WHERE
    COALESCE(ol.month_start, nr.month_start, cs.month_start, orm.month_start) >= DATE('2018-01-01')
)
SELECT
  *
FROM full_join
UNION ALL
SELECT
  *
FROM new_listings