with pre_online_metrics AS (
  WITH
  metrics AS (
        SELECT
          DATE_TRUNC('week', CAST(ts_event AS DATE)) AS event_date,
          id_user AS user_id,
          CASE WHEN event_type = 'listing_page_viewed' THEN uuid END AS listing_page_views,
          CASE WHEN event_type = 'schedule_page_viewed' THEN uuid END AS schedule_page_views,
          CASE WHEN event_type = 'tips_page_viewed' THEN uuid END AS tips_page_views,
          CASE WHEN event_type = 'tip_lowerprice_page_viewed' THEN uuid END AS tip_lowerprice_page_viewed,
          CASE WHEN event_type = 'tip_lowerprice_confirmed' THEN uuid END AS tip_lowerprice_confirmed,
          CASE WHEN event_type = 'tip_agendaavalilability_confirmed' THEN uuid END AS tip_agendaavalilability_confirmed,
          CASE WHEN event_type = 'tip_lockbox_confirmed' THEN uuid END AS tip_lockbox_confirmed,
          CASE WHEN event_type = 'tip_video_confirmed' THEN uuid END AS tip_video_confirmed,
          CASE WHEN event_type = 'tip_pets_confirmed' THEN uuid END AS tip_pets_confirmed,
          CASE WHEN event_type = 'tip_furniture_confirmed' THEN uuid END AS tip_furniture_confirmed,
          CASE WHEN event_type = 'tip_entrydate_confirmed' THEN uuid END AS tip_entrydate_confirmed,
          CASE WHEN event_type = 'tip_description_confirmed' THEN uuid END AS tip_description_confirmed,
          CASE WHEN event_type = 'tip_negotiation_confirmed' THEN uuid END AS tip_negotiation_confirmed
        FROM
          datalake_amplitude_clean_prod.events
        WHERE
          event_type IN ('listing_page_viewed', 'schedule_page_viewed', 'tips_page_viewed',
          'tip_video_confirmed', 'tip_pets_confirmed', 'tip_furniture_confirmed', 'tip_entrydate_confirmed',
          'tip_lowerprice_page_viewed', 'tip_lowerprice_confirmed', 'tip_description_confirmed', 'tip_negotiation_confirmed',
          'tip_agendaavalilability_confirmed', 'tip_lockbox_confirmed')
          AND platform IN ('Web', 'iOS')
          AND CAST(JSON_EXTRACT(user_properties, '$.platform') AS varchar) IN ('web_mobile', 'web_desktop', 'ios')
  )
  SELECT
      event_date,
      user_id,
      COUNT(DISTINCT listing_page_views) AS listing_page_views,
      COUNT(DISTINCT schedule_page_views) AS schedule_page_views,
      COUNT(DISTINCT tips_page_views) AS tips_page_views,
      COUNT(DISTINCT tip_lowerprice_page_viewed) AS tip_lowerprice_page_viewed,
      COUNT(DISTINCT tip_lowerprice_confirmed) AS tip_lowerprice_confirmed,
      COUNT(DISTINCT tip_agendaavalilability_confirmed) AS tip_agendaavalilability_confirmed,
      COUNT(DISTINCT tip_lockbox_confirmed) AS tip_lockbox_confirmed,
      COUNT(DISTINCT tip_video_confirmed) AS tip_video_confirmed,
      COUNT(DISTINCT tip_pets_confirmed) AS tip_pets_confirmed,
      COUNT(DISTINCT tip_furniture_confirmed) AS tip_furniture_confirmed,
      COUNT(DISTINCT tip_entrydate_confirmed) AS tip_entrydate_confirmed,
      COUNT(DISTINCT tip_description_confirmed) AS tip_description_confirmed,
      COUNT(DISTINCT tip_negotiation_confirmed) AS tip_negotiation_confirmed
  FROM
      metrics
  WHERE user_id <> ''
  GROUP BY 1, 2
),
online_metrics AS (
  SELECT
    DATE_TRUNC('week', m.event_date) AS date_period,
    'week' AS period,
    m.user_id,
    m.listing_page_views,
    m.schedule_page_views,
    m.tips_page_views,
    m.tip_lowerprice_page_viewed,
    m.tip_lowerprice_confirmed,
    m.tip_agendaavalilability_confirmed,
    m.tip_lockbox_confirmed,
    m.tip_video_confirmed,
    m.tip_pets_confirmed,
    m.tip_furniture_confirmed,
    m.tip_entrydate_confirmed,
    m.tip_description_confirmed,
    m.tip_negotiation_confirmed
  FROM
    pre_online_metrics AS m
  WHERE
    (
      m.event_date >= DATE_ADD('week', -24, CURRENT_DATE)
      OR DATE_TRUNC('week', m.event_date) = DATE_TRUNC('week', CURRENT_DATE)
    )
)
SELECT
  om.*,
  NOW() AS ts_load
FROM
  online_metrics AS om
