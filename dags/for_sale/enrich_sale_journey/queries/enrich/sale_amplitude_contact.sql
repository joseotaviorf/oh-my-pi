WITH amplitude_active_search AS (
  SELECT
    srp.id_user,
    'Active Search' AS action,
    srp.ts_event,
    DATE(srp.ts_event) AS date,
    srp.year,
    srp.month,
    srp.day
  FROM
    datalake_amplitude_clean.170698_search_results_page_viewed_events AS srp
  INNER JOIN
    datalake_amplitude_clean.170698_apply_filters_events AS apf
      ON apf.id_amplitude = srp.id_amplitude
      AND apf.year = srp.year
      AND apf.month = srp.month
      AND apf.day = srp.day
  INNER JOIN
    datalake_amplitude_clean.170698_listing_page_viewed_events AS lpv
      ON lpv.id_amplitude = apf.id_amplitude
      AND lpv.year = apf.year
      AND lpv.month = apf.month
      AND lpv.day = apf.day
  WHERE
      srp.year = {year}
      AND apf.year = {year}
      AND lpv.year = {year}
      AND srp.month = {month}
      AND apf.month = {month}
      AND lpv.month = {month}
      AND srp.day = {day}
      AND apf.day = {day}
      AND lpv.day = {day}
      AND NULLIF(srp.id_user, '') IS NOT NULL
      AND LOWER(GET_JSON_OBJECT(srp.event_properties, '$.business_context')) = 'sale'
),
amplitude_sale_tts_events AS (
  SELECT
    tts.id_user,
    'TALK_TO_SECRETARY' AS action,
    tts.ts_event,
    DATE(tts.ts_event) AS date,
    tts.year,
    tts.month,
    tts.day
  FROM
    datalake_amplitude_clean.170698_tts_success_page_viewed_events AS tts
  WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    AND NULLIF(tts.id_user, '') IS NOT NULL
    AND LOWER(GET_JSON_OBJECT(tts.event_properties, '$.business_context')) = 'sale'
),
union_base AS (
  SELECT
    id_user,
    action,
    ts_event,
    date,
    year,
    month,
    day
  FROM
    amplitude_active_search
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_user, date ORDER BY ts_event) = 1
  UNION ALL
  SELECT
    id_user,
    action,
    ts_event,
    date,
    year,
    month,
    day
  FROM
    amplitude_sale_tts_events
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_user, date ORDER BY ts_event) = 1
)

SELECT
  id_user,
  action,
  date AS dt_event,
  ts_event,
  year,
  month,
  day
FROM
  union_base
