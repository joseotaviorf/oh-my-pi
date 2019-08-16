with pre_online_metrics AS (
  WITH
  metrics AS (
        SELECT
          DATE_TRUNC('week', CAST(SUBSTRING(TRIM(evt.event_time), 1, 10) AS DATE)) AS event_date,
          TRIM(evt.user_id) AS user_id,
          CASE WHEN TRIM(evt.et) = 'listing_page_viewed' THEN evt.uuid END AS listing_page_views,
          CASE WHEN TRIM(evt.et) = 'schedule_page_viewed' THEN evt.uuid END AS schedule_page_views,
          CASE WHEN TRIM(evt.et) = 'tips_page_viewed' THEN evt.uuid END AS tips_page_views
        FROM datalake_clean.amplitude_events evt
        WHERE TRIM(evt.et) IN ('listing_page_viewed', 'schedule_page_viewed', 'tips_page_viewed')
          AND TRIM(platform) IN ('Web', 'iOS')
          AND TRIM(u_platform) IN ('web_mobile', 'web_desktop', 'ios')
          AND ym >= '2019-01'
    union
        SELECT
          DATE_TRUNC('week', CAST(SUBSTRING(TRIM(event_time), 1, 10) AS DATE)) AS event_date,
          coalesce(cast(json_extract(event_properties, '$.user_id') as varchar), '') as user_id,
          CASE WHEN event_type = 'listing_page_viewed' THEN uuid END AS listing_page_views,
          CASE WHEN event_type = 'schedule_page_viewed' THEN uuid END AS schedule_page_views,
          CASE WHEN event_type = 'tips_page_viewed' THEN uuid END AS tips_page_views
        FROM datalake_clean_spark.amplitude_events
        WHERE event_type IN ('listing_page_viewed', 'schedule_page_viewed', 'tips_page_viewed')
          AND year >= 2019
          AND platform IN ('Web', 'iOS')
          and cast(json_extract(user_properties, '$.platform') as varchar) IN ('web_mobile', 'web_desktop', 'ios')
  )
    select
        event_date,
        user_id,
        count(distinct listing_page_views) as listing_page_views,
        count(distinct schedule_page_views) as schedule_page_views,
        count(distinct tips_page_views) as tips_page_views
    from
        metrics
    where user_id <> ''
    group by 1, 2
),
online_metrics as (
  SELECT
    date_trunc('week', m.event_date) AS date_period,
    'week' AS period,
    m.user_id,
    m.listing_page_views,
    m.schedule_page_views,
    m.tips_page_views
  FROM pre_online_metrics m
  WHERE (m.event_date >= DATE_ADD('week', -24, CURRENT_DATE) OR DATE_TRUNC('week', m.event_date) = DATE_TRUNC('week', CURRENT_DATE))
)
SELECT
  om.*
FROM online_metrics om
