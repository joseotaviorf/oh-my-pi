WITH yesterday_stats AS (
  SELECT
    id_owner,
    COUNT(*) AS listing_count,
    SUM(
      CASE
        WHEN status_change_reason = 'RENTED' THEN 1
        ELSE 0
      END
    ) AS rented_listing_count
  FROM
    datalake_rental_historical_follow_up.house_listings_daily_info
  WHERE
    MAKE_DATE(year, month, day) = DATE('{load_start_date}')
  GROUP BY ALL
),
two_year_stats AS (
  SELECT
    id_owner,
    day,
    month,
    year,
    COUNT(1) AS daily_listing_count,
    SUM(
      CASE
        WHEN status_change_reason = 'RENTED' THEN 1
        ELSE 0
      END
    ) AS daily_rented_listing_count
  FROM
    datalake_rental_historical_follow_up.house_listings_daily_info
  WHERE
    MAKE_DATE(year, month, day) >= (DATE('{load_start_date}') - INTERVAL '2' YEAR)
  GROUP BY ALL
),
two_year_max AS (
  SELECT
    id_owner,
    MAX(daily_listing_count) AS max_listing_count,
    MAX(daily_rented_listing_count) AS max_rented_listing_count
  FROM
    two_year_stats
  GROUP BY
    id_owner
),
lifetime_stats AS (
  SELECT
    id_owner,
    day,
    month,
    year,
    COUNT(1) AS daily_listing_count,
    SUM(
      CASE
        WHEN status_change_reason = 'RENTED' THEN 1
        ELSE 0
      END
    ) AS daily_rented_listing_count
  FROM
    datalake_rental_historical_follow_up.house_listings_daily_info
  GROUP BY ALL
),
lifetime_max AS (
  SELECT
    id_owner,
    MAX(daily_listing_count) AS max_listing_count,
    MAX(daily_rented_listing_count) AS max_rented_listing_count
  FROM
    lifetime_stats
  GROUP BY
    id_owner
)
SELECT
  ys.id_owner,
  CASE
    WHEN
      (
        ys.listing_count >= 5
        AND ys.rented_listing_count >= 1
      )
    THEN 
      'ACTIVE'
    WHEN 
      (
        tym.max_listing_count >= 5
        AND tym.max_rented_listing_count >= 1
      )
    THEN
      'POTENTIAL'
    ELSE 'LIFETIME'
  END AS pp_multi_classification,
  ys.listing_count AS current_listings,
  ys.rented_listing_count AS current_rented_listings,
  tym.max_listing_count AS max_listing_in_two_years,
  tym.max_rented_listing_count AS max_rented_listing_in_two_years,
  lm.max_listing_count AS max_listing_in_lifetime,
  lm.max_rented_listing_count AS max_rented_listing_in_lifetime
FROM
  yesterday_stats AS ys
JOIN
  two_year_max AS tym
    ON ys.id_owner = tym.id_owner
JOIN 
  lifetime_max AS lm
    ON ys.id_owner = lm.id_owner
WHERE
  lm.max_listing_count >= 5
  AND lm.max_rented_listing_count >= 1
