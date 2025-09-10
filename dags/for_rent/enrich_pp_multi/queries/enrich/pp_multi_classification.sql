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
      ys.ongoing_houses >= 5
    THEN 
      'ACTIVE'
    WHEN 
      tym.max_ongoing_houses >= 5
    THEN
      'POTENTIAL'
    ELSE 'LIFETIME'
  END AS pp_multi_classification,
  ys.ongoing_houses AS ongoing_houses,
  tym.max_ongoing_houses AS max_ongoing_houses_in_two_years,
  lm.max_ongoing_houses AS max_ongoing_houses_in_lifetime,
  vlm.visits_booked AS visits_booked_last_month,
  vlm.visits_completed AS visits_completed_last_month
FROM
  yesterday_stats AS ys
JOIN
  two_year_max AS tym
    ON ys.id_owner = tym.id_owner
JOIN 
  lifetime_max AS lm
    ON ys.id_owner = lm.id_owner
JOIN
  visits_last_month AS vlm
    ON ys.id_owner = vlm.id_owner
WHERE
  lm.max_ongoing_houses >= 5
