WITH visits_last_month AS (
  SELECT
    id_owner,
    COUNT(DISTINCT IF(id_event_type = 1, id_event, NULL)) AS visits_booked,
    COUNT(DISTINCT IF(id_event_type = 2, id_event, NULL)) AS visits_completed
  FROM
    datalake_rent_demand_events.rent_demand_events
  WHERE
    ts_event >= DATE('{load_start_date}') - INTERVAL '1' MONTH
  GROUP BY ALL
),

ongoing_houses_stats AS (
  SELECT
    id_owner,
    day,
    month,
    year,
    COUNT(DISTINCT IF(status_history IN ('alugado', 'publicado', 'suspenso', 'SUSPENDED', 'PUBLISHED'), id_house, NULL)) AS ongoing_houses
  FROM
    datalake_rental_historical_follow_up.house_listings_daily_info
  GROUP BY ALL
),

yesterday_stats AS (
  SELECT
    ohs.id_owner,
    ohs.ongoing_houses
  FROM
    ongoing_houses_stats AS ohs
  WHERE
    MAKE_DATE(ohs.year, ohs.month, ohs.day) = DATE('{load_start_date}')
  GROUP BY ALL
),

two_year_max AS (
  SELECT
    ohs.id_owner,
    MAX(ohs.ongoing_houses) AS max_ongoing_houses
  FROM
    ongoing_houses_stats AS ohs
  WHERE
    MAKE_DATE(ohs.year, ohs.month, ohs.day) = DATE('{load_start_date}') - INTERVAL '2' YEAR
  GROUP BY ALL
),


lifetime_max AS (
  SELECT
    ohs.id_owner,
    MAX(ohs.ongoing_houses) AS max_ongoing_houses
  FROM
    ongoing_houses_stats AS ohs
  GROUP BY ALL
)

SELECT
  ys.id_owner,
  CASE
    WHEN
      COALESCE(ys.ongoing_houses, 0) >= 5
    THEN 
      'ACTIVE'
    WHEN 
      COALESCE(tym.max_ongoing_houses, 0) >= 5
    THEN
      'POTENTIAL'
    ELSE 'LIFETIME'
  END AS pp_multi_classification,
  COALESCE(ys.ongoing_houses, 0) AS ongoing_houses,
  COALESCE(tym.max_ongoing_houses, 0) AS max_ongoing_houses_in_two_years,
  COALESCE(lm.max_ongoing_houses, 0) AS max_ongoing_houses_in_lifetime,
  COALESCE(vlm.visits_booked, 0) AS visits_booked_last_month,
  COALESCE(vlm.visits_completed, 0) AS visits_completed_last_month
FROM
  lifetime_max AS lm
LEFT JOIN 
  yesterday_stats AS ys
    ON lm.id_owner = ys.id_owner
LEFT JOIN
  two_year_max AS tym
    ON lm.id_owner = tym.id_owner
LEFT JOIN
  visits_last_month AS vlm
    ON lm.id_owner = vlm.id_owner
WHERE
  lm.max_ongoing_houses >= 5
