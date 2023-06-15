WITH events AS (
  SELECT DISTINCT
    id_user,
    ts_event
  FROM
    datalake_amplitude_clean_staging.170698_af_app_opened_events
  WHERE
    year >= 2023
  UNION ALL
  SELECT DISTINCT
    id_user,
    ts_event
  FROM
    datalake_amplitude_clean_staging.170698_home_page_viewed_events
  WHERE
    year >= 2023
    AND platform IN ('Android','iOS')
  UNION ALL
  SELECT DISTINCT
    id_user,
    ts_event
  FROM
    datalake_amplitude_clean_staging.170698_search_page_viewed_events
  WHERE
    year >= 2023
    AND platform IN ('Android','iOS')
  UNION ALL
  SELECT DISTINCT
    id_user,
    ts_event
  FROM
    datalake_amplitude_clean_staging.170698_login_page_viewed_events
  WHERE
    year >= 2023
    AND platform IN ('Android','iOS')
)

SELECT
  COALESCE(id_user, -1) AS id_user,
  MAX(ts_event) AS ts_last_event
FROM
  events
GROUP BY 1
