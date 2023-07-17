WITH user_latest_app_event AS (
    SELECT
      id_user,
      MAX(ts_event) AS ts_last_app_installed
    FROM
      datalake_app_installed.events
    WHERE
      DATE(ts_event) <= DATE('{year}-{month}-{day}')
      AND id_user IS NOT NULL
    GROUP BY 1
)
SELECT
  DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd') AS id_snapshot,
  id_user,
  CASE
    WHEN DATEDIFF(DATE('{year}-{month}-{day}'), ts_last_app_installed) <= 45 THEN TRUE
    ELSE FALSE
  END AS has_app_installed,
  ts_last_app_installed,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  user_latest_app_event
