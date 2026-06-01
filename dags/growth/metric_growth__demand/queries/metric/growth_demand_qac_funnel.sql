WITH clean_events AS (
  SELECT
    ui.id_amplitude,
    dr.city_group,
    ui.is_qac,
    ui.is_qac_region,
    ui.business_context,
    ui.tof_event_type AS event_type,
    CASE
      WHEN ui.app_type IS NULL THEN 'Lost Tracking'
      WHEN LOWER(ui.app_type) LIKE '%android%' THEN 'App Android'
      WHEN LOWER(ui.app_type) LIKE '%ios%' THEN 'App iOS'
      WHEN LOWER(ui.app_type) LIKE '%web%' THEN 'Web'
      ELSE 'Other'
    END AS platform,
    ui.ts_event
  FROM
    datalake_top_of_funnel_demand.user_interactions AS ui
  LEFT JOIN
    dw_public.dim_region AS dr
      ON dr.sk_region = ui.sk_region
  WHERE
    MAKE_DATE(ui.year, ui.month, ui.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND DATE(ui.ts_event) BETWEEN '{load_start_date}' AND '{load_end_date}'

  UNION ALL

  SELECT
    qac.id_amplitude,
    dr.city_group,
    qac.is_qac,
    TRUE AS is_qac_region,
    qac.business_context,
    qac.event_type,
    CASE
      WHEN qac.platform IS NULL THEN 'Lost Tracking'
      WHEN LOWER(qac.platform) LIKE '%android%' THEN 'App Android'
      WHEN LOWER(qac.platform) LIKE '%ios%' THEN 'App iOS'
      WHEN LOWER(qac.platform) LIKE '%web%' THEN 'Web'
      ELSE 'Other'
    END AS platform,
    qac.ts_event
  FROM
    datalake_top_of_funnel_demand.quintoandar_classifieds_events AS qac
  LEFT JOIN
    dw_public.dim_region AS dr
      ON dr.sk_region = qac.id_region
  WHERE
    MAKE_DATE(qac.year, qac.month, qac.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND DATE(qac.ts_event) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
funnel_metrics AS (
  SELECT
    DATE(ts_event) AS dt_reference,
    '1. ToF' AS metric_name,
    business_context,
    city_group,
    platform,
    COUNT(DISTINCT id_amplitude) AS metric_value
  FROM
    clean_events
  WHERE
    event_type IN ('search_page_viewed', 'search_results_page_viewed', 'listing_page_viewed', 'schedule_page_viewed')
  GROUP BY 1, 2, 3, 4, 5

  UNION ALL

  SELECT
    DATE(ts_event) AS dt_reference,
    '2. ToF QAC' AS metric_name,
    business_context,
    city_group,
    platform,
    COUNT(DISTINCT id_amplitude) AS metric_value
  FROM
    clean_events
  WHERE
    is_qac_region = TRUE
    AND event_type IN ('search_page_viewed', 'search_results_page_viewed', 'listing_page_viewed')
  GROUP BY 1, 2, 3, 4, 5

  UNION ALL

  SELECT
    DATE(ts_event) AS dt_reference,
    '3. ToF QAC Listed' AS metric_name,
    business_context,
    city_group,
    platform,
    COUNT(DISTINCT id_amplitude) AS metric_value
  FROM
    clean_events
  WHERE
    is_qac = TRUE
    AND event_type IN ('search_page_viewed', 'search_results_page_viewed', 'listing_page_viewed')
  GROUP BY 1, 2, 3, 4, 5

  UNION ALL

  SELECT
    DATE(ts_event) AS dt_reference,
    '4. Listing' AS metric_name,
    business_context,
    city_group,
    platform,
    COUNT(DISTINCT id_amplitude) AS metric_value
  FROM
    clean_events
  WHERE
    is_qac = TRUE
    AND event_type IN ('listing_page_viewed')
  GROUP BY 1, 2, 3, 4, 5

  UNION ALL

  SELECT
    DATE(ts_event) AS dt_reference,
    CASE
      WHEN event_type = 'lead_intent' THEN '5. Lead Intent'
      WHEN event_type = 'lead_intent_confirmed' THEN '6. Lead Confirmed'
    END AS metric_name,
    business_context,
    city_group,
    platform,
    COUNT(DISTINCT id_amplitude) AS metric_value
  FROM
    clean_events
  WHERE
    event_type IN ('lead_intent', 'lead_intent_confirmed')
  GROUP BY 1, 2, 3, 4, 5

  UNION ALL

  SELECT
    DATE(ts_event) AS dt_reference,
    'Search' AS metric_name,
    business_context,
    city_group,
    platform,
    COUNT(DISTINCT id_amplitude) AS metric_value
  FROM
    clean_events
  WHERE
    event_type IN ('search_results_page_viewed', 'search_page_viewed')
  GROUP BY 1, 2, 3, 4, 5

  UNION ALL

  SELECT
    DATE(search_.ts_event) AS dt_reference,
    'Search > LPV' AS metric_name,
    search_.business_context,
    search_.city_group,
    search_.platform,
    COUNT(DISTINCT search_.id_amplitude) AS metric_value
  FROM
    clean_events AS search_
  INNER JOIN
    clean_events AS lpv_
      ON search_.id_amplitude = lpv_.id_amplitude
        AND DATE(search_.ts_event) = DATE(lpv_.ts_event)
        AND lpv_.event_type = 'listing_page_viewed'
  WHERE
    search_.event_type IN ('search_results_page_viewed', 'search_page_viewed')
  GROUP BY 1, 2, 3, 4, 5
)
SELECT
  dt_reference,
  metric_name,
  business_context,
  city_group,
  platform,
  metric_value,
  YEAR(dt_reference) AS year,
  MONTH(dt_reference) AS month,
  DAY(dt_reference) AS day
FROM
  funnel_metrics
