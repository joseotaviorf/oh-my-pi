WITH
dates AS (
  SELECT DATE(d.date) AS date_day
  FROM datalake_clean.ods_dim_date d
  WHERE d.sk_date != '-1'
    AND DATE(d.date) >= DATE_ADD('week', -2, CURRENT_DATE)
    AND DATE_TRUNC('week', DATE(d.date)) <= DATE_TRUNC('week', CURRENT_DATE)
),
days_published AS (
  WITH
  published AS (
    SELECT
      sk_house AS sk_house_listing,
      SUBSTRING(sk_house, 1, 9) AS sk_house,
      DATE_PARSE(sk_min_status_date, '%Y%m%d') AS min_status_date,
      COALESCE(TRY(DATE_PARSE(sk_max_status_date, '%Y%m%d')), CURRENT_DATE) AS max_status_date
    FROM datalake_clean.ods_fact_house_status
    WHERE status_history = 'publicado'
  ),
  rows AS (
    SELECT
      *,
      ROW_NUMBER() OVER(PARTITION BY sk_house, max_status_date ORDER BY max_status_date ASC) AS row
    FROM published
  )
  -- HACK: fact_house_status has an issue where it can have two rows with a published status and null max_status_date
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
online_metrics AS (
  WITH
  metrics AS (
    SELECT
      DATE_TRUNC('week', CAST(regexp_extract(TRIM(evt.event_time), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) AS TIMESTAMP)) AS event_timestamp,
      TRIM(evt.e_house_id) AS house_id,
      COUNT(DISTINCT CASE WHEN TRIM(evt.et) = 'listing_page_viewed' THEN evt.uuid END) AS listing_page_views,
      COUNT(DISTINCT CASE WHEN TRIM(evt.et) = 'schedule_page_viewed' THEN evt.uuid END) AS schedule_page_views,
      COUNT(DISTINCT CASE WHEN TRIM(evt.et) = 'tips_page_viewed' THEN evt.uuid END) AS tips_page_views
    FROM datalake_clean.amplitude_events evt
    WHERE TRIM(evt.et) IN ('listing_page_viewed', 'schedule_page_viewed', 'tips_page_viewed')
      AND TRIM(platform) IN ('Web', 'iOS')
      AND TRIM(u_platform) IN ('web_mobile', 'web_desktop', 'ios')
      AND ym >= '2019-01'
    GROUP BY 1, 2
  )
  SELECT
    date_trunc('week', m.event_timestamp) AS date_period,
    'week' AS period,
    dp.sk_house_listing,
    m.listing_page_views,
    m.schedule_page_views,
    m.tips_page_views
  FROM metrics m
  JOIN days_published dp
    ON m.house_id = dp.sk_house AND m.event_timestamp BETWEEN dp.min_status_date AND dp.max_status_date
  WHERE (m.event_timestamp >= DATE_ADD('week', -2, CURRENT_DATE) OR DATE_TRUNC('week', m.event_timestamp) = DATE_TRUNC('week', CURRENT_DATE))
)
SELECT
  om.*,
  pp.days_published_in_period
FROM online_metrics om
LEFT JOIN days_published_in_period pp
  ON pp.sk_house_listing = om.sk_house_listing AND pp.date_period = om.date_period
