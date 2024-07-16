SELECT
  site_url,
  type,
  keys[0] AS page,
  keys[1] AS country,
  CAST(clicks AS INT) AS clicks,
  CAST(impressions AS INT) AS impressions,
  CAST(ctr AS DOUBLE) AS ctr,
  CAST(position AS DOUBLE) AS position,
  CAST(position*impressions AS DOUBLE) AS posimp,
  date AS dt_created,
  YEAR(date) AS year,
  MONTH(date) AS month,
  DAY(date) AS day
FROM
    datalake_google_search_console_raw.report_by_discover
WHERE
    date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')