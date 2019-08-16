with pre_online_metrics AS (
  WITH
  metrics AS (
        SELECT
          DATE_TRUNC('week', CAST(SUBSTRING(TRIM(evt.event_time), 1, 10) AS DATE)) AS event_date,
          TRIM(evt.user_id) AS user_id,
          CASE WHEN TRIM(evt.et) = 'listing_page_viewed' THEN evt.uuid END AS listing_page_views,
          CASE WHEN TRIM(evt.et) = 'schedule_page_viewed' THEN evt.uuid END AS schedule_page_views,
          CASE WHEN TRIM(evt.et) = 'tips_page_viewed' THEN evt.uuid END AS tips_page_views,
          CASE WHEN TRIM(evt.et) = 'tip_lowerprice_page_viewed' THEN evt.uuid END AS tip_lowerprice_page_viewed,
          CASE WHEN TRIM(evt.et) = 'tip_lowerprice_confirmed' THEN evt.uuid END AS tip_lowerprice_confirmed,
          CASE WHEN TRIM(evt.et) = 'tip_agendaavalilability_confirmed' THEN evt.uuid END AS tip_agendaavalilability_confirmed,
          CASE WHEN TRIM(evt.et) = 'tip_lockbox_confirmed' THEN evt.uuid END AS tip_lockbox_confirmed,
          CASE WHEN TRIM(evt.et) = 'tip_video_confirmed' THEN evt.uuid END AS tip_video_confirmed,
          CASE WHEN TRIM(evt.et) = 'tip_pets_confirmed' THEN evt.uuid END AS tip_pets_confirmed,
          CASE WHEN TRIM(evt.et) = 'tip_furniture_confirmed' THEN evt.uuid END AS tip_furniture_confirmed,
          CASE WHEN TRIM(evt.et) = 'tip_entrydate_confirmed' THEN evt.uuid END AS tip_entrydate_confirmed,
          CASE WHEN TRIM(evt.et) = 'tip_description_confirmed' THEN evt.uuid END AS tip_description_confirmed,
          CASE WHEN TRIM(evt.et) = 'tip_negotiation_confirmed' THEN evt.uuid END AS tip_negotiation_confirmed
        FROM datalake_clean.amplitude_events evt
        WHERE TRIM(evt.et) IN ('listing_page_viewed', 'schedule_page_viewed', 'tips_page_viewed',
                             'tip_video_confirmed', 'tip_pets_confirmed', 'tip_furniture_confirmed', 'tip_entrydate_confirmed',
                               'tip_lowerprice_page_viewed', 'tip_lowerprice_confirmed', 'tip_description_confirmed', 'tip_negotiation_confirmed')
          AND TRIM(platform) IN ('Web', 'iOS')
          AND TRIM(u_platform) IN ('web_mobile', 'web_desktop', 'ios')
          AND ym >= '2019-01'
    union
        SELECT
          DATE_TRUNC('week', CAST(SUBSTRING(TRIM(event_time), 1, 10) AS DATE)) AS event_date,
          coalesce(cast(json_extract(event_properties, '$.user_id') as varchar), '') as user_id,
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
        FROM datalake_amplitude_clean_prod.events
        WHERE event_type IN ('listing_page_viewed', 'schedule_page_viewed', 'tips_page_viewed',
                             'tip_video_confirmed', 'tip_pets_confirmed', 'tip_furniture_confirmed', 'tip_entrydate_confirmed',
                             'tip_lowerprice_page_viewed', 'tip_lowerprice_confirmed', 'tip_description_confirmed', 'tip_negotiation_confirmed')
          AND year >= 2019
          AND platform IN ('Web', 'iOS')
          and cast(json_extract(user_properties, '$.platform') as varchar) IN ('web_mobile', 'web_desktop', 'ios')
  )
    select
        event_date,
        user_id,
        count(distinct listing_page_views) as listing_page_views,
        count(distinct schedule_page_views) as schedule_page_views,
        count(distinct tips_page_views) as tips_page_views,
        count(distinct tip_lowerprice_page_viewed) as tip_lowerprice_page_viewed,
        count(distinct tip_lowerprice_confirmed) as tip_lowerprice_confirmed,
        count(distinct tip_agendaavalilability_confirmed) as tip_agendaavalilability_confirmed,
        count(distinct tip_lockbox_confirmed) as tip_lockbox_confirmed,
        count(distinct tip_video_confirmed) as tip_video_confirmed,
        count(distinct tip_pets_confirmed) as tip_pets_confirmed,
        count(distinct tip_furniture_confirmed) as tip_furniture_confirmed,
        count(distinct tip_entrydate_confirmed) as tip_entrydate_confirmed,
        count(distinct tip_description_confirmed) as tip_description_confirmed,
        count(distinct tip_negotiation_confirmed) as tip_negotiation_confirmed
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
  FROM pre_online_metrics m
  WHERE (m.event_date >= DATE_ADD('week', -24, CURRENT_DATE) OR DATE_TRUNC('week', m.event_date) = DATE_TRUNC('week', CURRENT_DATE))
)
SELECT
  om.*
FROM online_metrics om
