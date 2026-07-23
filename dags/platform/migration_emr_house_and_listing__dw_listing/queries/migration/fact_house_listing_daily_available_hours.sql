WITH house_listings AS (
  SELECT
    sk_date,
    sk_house,
    sk_house_listing,
    is_brz_business_day,
    week_day,
    week_start,
    date,
    year,
    month,
    day
  FROM (
    SELECT
      d.id_date AS sk_date,
      hls.id_house AS sk_house,
      hls.id_house_listing AS sk_house_listing,
      d.is_brz_business_day,
      d.week_day,
      d.week_start,
      d.date,
      d.year,
      d.month,
      d.day,
      ROW_NUMBER() OVER (PARTITION BY hls.id_house_listing, d.date ORDER BY hls.ts_status_started DESC) AS _w,
      hls.id_house_listing,
      hls.ts_status_started
    FROM datalake_ebdb_listing.house_listing_status AS hls
    JOIN datalake_quintoandar.aux_date AS d
      ON d.date BETWEEN CAST(hls.ts_status_started AS DATE) AND COALESCE(CAST(hls.ts_status_ended AS DATE), CURRENT_DATE) - 1
    WHERE
      MAKE_DATE(d.year, d.month, d.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
      AND hls.status_history IN ('publicado', 'PUBLISHED')
      AND hls.version <> 0
  ) AS _t
  WHERE
    _w = 1
), available_hours AS (
  SELECT
    sk_house_listing_date,
    sk_house,
    sk_house_listing,
    sk_date,
    week_start,
    day_hours_available,
    is_brz_business_day,
    week_day,
    year,
    month,
    day
  FROM (
    SELECT
      CONCAT(hl.sk_house_listing, hl.sk_date) AS sk_house_listing_date,
      hl.sk_house,
      hl.sk_house_listing,
      hl.sk_date,
      hl.week_start,
      hah.day_hours_available,
      hl.is_brz_business_day,
      hl.week_day,
      hl.year,
      hl.month,
      hl.day,
      ROW_NUMBER() OVER (PARTITION BY hl.sk_house_listing, hl.sk_date ORDER BY hah.dt_available_started DESC) AS _w,
      hah.dt_available_started
    FROM house_listings AS hl
    LEFT JOIN datalake_booking.house_available_hours AS hah
      ON hah.id_house = hl.sk_house
      AND hl.date BETWEEN hah.dt_available_started AND COALESCE(hah.dt_available_ended, CURRENT_DATE)
      AND hl.week_day = IF(hah.day_of_week = 7, 0, hah.day_of_week)
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  sk_house_listing_date,
  sk_house,
  sk_house_listing,
  sk_date,
  day_hours_available AS day_available_hours,
  SUM(day_hours_available) OVER (PARTITION BY sk_house_listing, week_start) AS week_available_hours,
  SUM(IF(is_brz_business_day, day_hours_available, 0)) OVER (PARTITION BY sk_house_listing, week_start) AS workdays_available_hours,
  week_day,
  NOW() AS ts_load,
  year,
  month,
  day
FROM available_hours
