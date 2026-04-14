SELECT
  id_anonymous AS device_id,
  egw_last_attribution_time AS attribution_time,
  egw_gclid AS gclid,
  egw_utm_term AS utm_term,
  egw_utm_source AS utm_source,
  egw_utm_medium AS utm_medium,
  egw_utm_content AS utm_content,
  egw_utm_campaign AS utm_campaign,
  ts_event,
  year,
  month,
  day
FROM datalake_cdp_clean.user_tracking
WHERE
  event_name <> '$identify'
  AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY 
    id_anonymous,
    egw_gclid,
    egw_utm_term,
    egw_utm_source,
    egw_utm_medium,
    egw_utm_content,
    egw_utm_campaign
  ORDER BY egw_last_attribution_time DESC
) = 1
