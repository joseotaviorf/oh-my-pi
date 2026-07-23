WITH user_latest_app_event AS (
  SELECT
    id_user,
    MAX(ts_event) AS ts_last_app_installed
  FROM datalake_app_installed.events
  WHERE
    CAST(ts_event AS DATE) <= CAST('{year}-{month}-{day}' AS DATE)
    AND NOT id_user IS NULL
  GROUP BY
    1
), user_latest_app_version AS (
  SELECT
    id_user,
    app_version
  FROM (
    SELECT
      id_user,
      app_version,
      ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY ts_event DESC) AS _w,
      ts_event
    FROM datalake_app_installed.events
    WHERE
      CAST(ts_event AS DATE) <= CAST('{year}-{month}-{day}' AS DATE)
      AND NOT id_user IS NULL
      AND NOT app_version IS NULL
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  DATE_FORMAT(CAST('{year}-{month}-{day}' AS DATE), 'yyyyMMdd') AS id_snapshot,
  lae.id_user,
  lav.app_version,
  CASE
    WHEN DATEDIFF(TO_DATE(CAST('{year}-{month}-{day}' AS DATE)), TO_DATE(lae.ts_last_app_installed)) <= 45
    THEN TRUE
    ELSE FALSE
  END AS has_app_installed,
  lae.ts_last_app_installed,
  STRUCT(year AS year) AS year,
  STRUCT(month AS month) AS month,
  STRUCT(day AS day) AS day
FROM user_latest_app_event AS lae
LEFT JOIN user_latest_app_version AS lav
  ON lav.id_user = lae.id_user
