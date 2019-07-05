WITH
online_metrics AS (
  SELECT
  	DATE_TRUNC('week', CAST(SUBSTRING(event_time, 1, 10) AS DATE)) AS event_date,
  	TRIM(evt.e_house_id) AS house_id,
    COUNT(DISTINCT CASE WHEN TRIM(evt.et) = 'listing_page_viewed' THEN evt.uuid END) AS listing_page_views,
    COUNT(DISTINCT CASE WHEN TRIM(evt.et) = 'schedule_page_viewed' THEN evt.uuid END) AS schedule_page_views
  FROM datalake_clean.amplitude_events evt
  	WHERE TRIM(evt.et) IN ('listing_page_viewed', 'schedule_page_viewed')
  	AND TRIM(app) = '170698'
  	AND ym >= '2019-05'
  GROUP BY 1, 2
),
houses AS (
  SELECT DISTINCT
      SUBSTRING(lf.sk_house_listing, 1, 9) AS house_id,
      lf.sk_region
  FROM public.fact_house_listing_flows lf
  WHERE lf.sk_house_listing > 0
),
online_metrics_by_house AS (
  SELECT
		DATE_TRUNC('week', om.event_date) AS date_period,
    h.house_id,
    SUM(listing_page_views) AS listing_page_views,
    SUM(schedule_page_views) AS schedule_page_views
  FROM online_metrics om
  JOIN houses h ON om.house_id = h.house_id
  WHERE event_date >= DATE_ADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', event_date) = DATE_TRUNC('week', CURRENT_DATE)
  GROUP BY 1, 2
),
visits_booked AS (
  SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_listing_rent_flows.sk_house_listing,
  	COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_booking  >= 0) THEN fact_listing_rent_flows.sk_booking  ELSE NULL END) AS visits_booked
	FROM public.fact_listing_rent_flows AS fact_listing_rent_flows
	LEFT JOIN public.dim_date ON fact_listing_rent_flows.sk_booking_created_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
	GROUP BY 1, 2
),
visits_completed AS (
  SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_listing_rent_flows.sk_house_listing,
    COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_booking  >= 0) AND (fact_listing_rent_flows.flg_visit_completed  > 0) THEN fact_listing_rent_flows.sk_booking  ELSE NULL END) AS visits_completed
  FROM public.fact_listing_rent_flows AS fact_listing_rent_flows
  LEFT JOIN public.dim_date ON fact_listing_rent_flows.sk_booking_created_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
  GROUP BY 1, 2
),
dates AS (
  SELECT d.date AS date_day
  FROM dim_date d
  WHERE d.date >= DATE_ADD('week', -12, CURRENT_DATE) AND DATE_TRUNC('week', d.date) <= DATE_TRUNC('week', CURRENT_DATE)
),
days_published AS (
  SELECT
    sk_house AS sk_house_listing,
    DATE(sk_min_status_date) AS min_status_date,
    COALESCE(DATE(sk_max_status_date), CURRENT_DATE) AS max_status_date
  FROM fact_house_status
  WHERE status_history = 'publicado'
),
days_published_in_period AS (
  SELECT
    DATE_TRUNC('week', date_day) AS date_period,
    sk_house_listing,
    COUNT(*) AS days_published_in_period
  FROM
    (
      SELECT
        d.date_day,
        dp.sk_house_listing
      FROM dates d
      LEFT JOIN days_published dp
        ON d.date_day >= dp.min_status_date AND d.date_day <= dp.max_status_date
    )
  GROUP BY 1, 2
),
metrics AS (
  SELECT
    *
  FROM visits_booked vb
  FULL OUTER JOIN visits_completed vc USING(date_period, sk_house_listing)
  FULL OUTER JOIN days_published_in_period dp USING(date_period, sk_house_listing)
)
SELECT
  DATE_TRUNC('week', d.date_day) AS date_period,
  m.sk_house_listing,
  m.visits_booked,
  m.visits_completed,
  COALESCE(m.days_published_in_period, 0) AS days_published_in_period
FROM dates d
LEFT JOIN metrics m ON m.date_period = DATE_TRUNC('week', d.date_day)
