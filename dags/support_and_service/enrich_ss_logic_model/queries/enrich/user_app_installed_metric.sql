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
),
user_latest_app_version AS (
  SELECT
    id_user,
    app_version
  FROM
    datalake_app_installed.events
  WHERE
    DATE(ts_event) <= DATE('{year}-{month}-{day}')
    AND id_user IS NOT NULL
    AND app_version IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY ts_event DESC) = 1
)
SELECT
  DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd') AS id_snapshot,
  lae.id_user,
  lav.app_version,
  CASE
    WHEN DATEDIFF(DATE('{year}-{month}-{day}'), lae.ts_last_app_installed) <= 45 THEN TRUE
    ELSE FALSE
  END AS has_app_installed,
  lae.ts_last_app_installed,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  user_latest_app_event AS lae
LEFT JOIN
  user_latest_app_version AS lav
    ON lav.id_user = lae.id_user
