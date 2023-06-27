SELECT DISTINCT
  REGEXP_REPLACE(id_user, "\\.", "") AS id_user,
  ts_event
FROM
  datalake_amplitude_clean_staging.170698_af_app_opened_events
WHERE
  year >= 2022
  AND platform IN ('Android', 'iOS')
  AND id_user IS NOT NULL
UNION ALL
SELECT DISTINCT
  REGEXP_REPLACE(id_user, "\\.", "") AS id_user,
  ts_event
FROM
  datalake_amplitude_clean_staging.170698_home_page_viewed_events
WHERE
  year >= 2022
  AND platform IN ('Android', 'iOS')
  AND id_user IS NOT NULL
UNION ALL
SELECT DISTINCT
  REGEXP_REPLACE(id_user, "\\.", "") AS id_user,
  ts_event
FROM
  datalake_amplitude_clean_staging.170698_search_page_viewed_events
WHERE
  year >= 2022
  AND platform IN ('Android', 'iOS')
  AND id_user IS NOT NULL
UNION ALL
SELECT DISTINCT
  REGEXP_REPLACE(id_user, "\\.", "") AS id_user,
  ts_event
FROM
  datalake_amplitude_clean_staging.170698_login_page_viewed_events
WHERE
  year >= 2022
  AND platform IN ('Android', 'iOS')
  AND id_user IS NOT NULL
