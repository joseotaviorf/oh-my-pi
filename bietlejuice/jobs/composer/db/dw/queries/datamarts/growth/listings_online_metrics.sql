WITH
dates AS (
  SELECT DATE(d.date) AS date_day
  FROM datalake_clean.ods_dim_date d
  WHERE d.sk_date != '-1'
    AND DATE(d.date) >= DATE_ADD('week', -24, CURRENT_DATE)
    AND DATE_TRUNC('week', DATE(d.date)) <= DATE_TRUNC('week', CURRENT_DATE)
),
days_published AS (
  WITH
  published AS (
    SELECT
      sk_house_listing,
      CASE WHEN sk_house_listing <> -1 THEN SUBSTRING(cast(sk_house_listing as varchar), 1, 9) ELSE '-1' END AS sk_house,
      CASE WHEN sk_status_start_date <> -1 THEN DATE_PARSE(cast(sk_status_start_date as varchar), '%Y%m%d') ELSE NULL END AS min_status_date,
      COALESCE(CASE WHEN sk_status_end_date <> -1 THEN DATE_PARSE(cast(sk_status_end_date as varchar), '%Y%m%d') ELSE NULL END, CURRENT_DATE) AS max_status_date
    FROM datalake_clean.ods_fact_house_listing_status
    WHERE status_history = 'publicado'
  ),
  rows AS (
    SELECT
      *,
      ROW_NUMBER() OVER(PARTITION BY sk_house, max_status_date ORDER BY max_status_date ASC) AS row
    FROM published
  )
  -- HACK: fact_house_listing_status has an issue where it can have two rows with a published status and null max_status_date
  -- while we don't fix that, here we will take only the first row
  SELECT * FROM rows WHERE row = 1
),
days_published_in_period AS (
  SELECT
    DATE_TRUNC('week', date_day) AS date_period,
    sk_house_listing,
    COUNT(*) AS days_published_in_period
  FROM
    (SELECT
      d.date_day,
      dp.sk_house_listing
    FROM dates d
    LEFT JOIN days_published dp
      ON d.date_day >= dp.min_status_date AND d.date_day < dp.max_status_date)
  GROUP BY 1, 2
),
pre_online_metrics AS (
  WITH
  metrics AS (
        SELECT
          DATE_TRUNC('week', CAST(ts_event AS DATE)) AS event_date,
          coalesce(cast(json_extract(event_properties, '$.house_id') as varchar), '') as house_id,
          CASE WHEN event_type = 'listing_page_viewed' THEN uuid END AS listing_page_views,
          CASE WHEN event_type = 'schedule_page_viewed' THEN uuid END AS schedule_page_views,
          CASE WHEN event_type = 'tips_page_viewed' THEN uuid END AS tips_page_views
        FROM datalake_amplitude_clean_prod.events
        WHERE event_type IN ('listing_page_viewed', 'schedule_page_viewed', 'tips_page_viewed')
          AND platform IN ('Web', 'iOS')
          and cast(json_extract(user_properties, '$.platform') as varchar) IN ('web_mobile', 'web_desktop', 'ios')
  )
    select
        event_date,
        house_id,
        count(distinct listing_page_views) as listing_page_views,
        count(distinct schedule_page_views) as schedule_page_views,
        count(distinct tips_page_views) as tips_page_views
    from
        metrics
    group by 1, 2
),
online_metrics as (
  SELECT
    date_trunc('week', m.event_date) AS date_period,
    'week' AS period,
    dp.sk_house_listing,
    m.listing_page_views,
    m.schedule_page_views,
    m.tips_page_views,
    NOW() as ts_load
  FROM pre_online_metrics m
  JOIN days_published dp
    ON m.house_id = dp.sk_house AND m.event_date BETWEEN dp.min_status_date AND dp.max_status_date
  WHERE (m.event_date >= DATE_ADD('week', -24, CURRENT_DATE) OR DATE_TRUNC('week', m.event_date) = DATE_TRUNC('week', CURRENT_DATE))
)
SELECT
  om.*,
  pp.days_published_in_period
FROM online_metrics om
LEFT JOIN days_published_in_period pp
  ON pp.sk_house_listing = om.sk_house_listing AND pp.date_period = om.date_period
