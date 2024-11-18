SELECT DISTINCT
  REGEXP_REPLACE(id_user, "\\.", "") AS id_user,
  CASE -- remove values on version_name that are timestamps and not version numbers
    WHEN TIMESTAMP(version_name) IS NULL
      OR SIZE(SPLIT(version_name, '.')) = 3 THEN version_name
    ELSE NULL
  END AS app_version,
  ts_event
FROM
  datalake_amplitude_clean.events
WHERE
  MAKE_DATE(year, month, day) >= DATE('{load_start_date}') - INTERVAL 6 MONTH
  AND id_user NOT IN ('false', 'userId')
  AND id_user IS NOT NULL
  AND id_app IN (170698, 183047)
  AND event_type IN (
    'search_page_viewed',
    'af_app_opened',
    'home_page_viewed',
    'login_page_viewed'
  )
