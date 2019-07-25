-- parametriza;
-- 'week', -12, etc.
WITH
contracts_signed AS (
	SELECT
		DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_listing_rent_flows.sk_region,
		COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_contract_signed_date  >= 0) THEN fact_listing_rent_flows.sk_contract  ELSE NULL END) AS contracts_signed,
    COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_contract_signed_date  >= 0) AND (fact_listing_rent_flows.days_offer_submitted_to_contract_signed <= 7) THEN fact_listing_rent_flows.sk_contract  ELSE NULL END) AS contracts_signed_7_days
	FROM public.fact_listing_rent_flows AS fact_listing_rent_flows
	JOIN public.dim_date ON fact_listing_rent_flows.sk_contract_signed_date = dim_date.sk_date
	WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
	GROUP BY 1, 2
),
visits_booked AS (
  SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_listing_rent_flows.sk_region,
  	COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_booking  >= 0) THEN fact_listing_rent_flows.sk_booking  ELSE NULL END) AS visits_booked
	FROM public.fact_listing_rent_flows AS fact_listing_rent_flows
	JOIN public.dim_date ON fact_listing_rent_flows.sk_booking_created_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
	GROUP BY 1, 2
),
ongoing_listings AS (
  SELECT
    DATE_TRUNC('week', olsl.week_start) AS date_period,
    fhl.sk_region,
    COUNT(DISTINCT CASE WHEN olsl.status_history = 'publicado' THEN olsl.sk_house_listing END) AS ongoing_listings
  FROM datamarts.ongoing_listed_suspended_listings olsl
  LEFT JOIN public.fact_house_listings fhl ON olsl.sk_house_listing = fhl.sk_house_listing
  WHERE olsl.week_start >= DATEADD('week', -12, CURRENT_DATE)
  GROUP BY 1, 2
),
ongoing_rentals AS (
	SELECT
	  dim_date.date_week AS date_period,
		sk_region,
		COUNT(*) AS ongoing_rentals
	FROM public.dim_contract AS dc
	JOIN public.fact_listing_rent_flows USING(sk_contract)
	JOIN (SELECT DATE_TRUNC('week', "date") AS date_week FROM public.dim_date GROUP BY 1) AS dim_date
	  ON dim_date.date_week >= DATE_TRUNC('week', dc.dt_start)
			 AND dim_date.date_week <= DATE_TRUNC('week', CURRENT_DATE)
			 AND dim_date.date_week >= DATE_TRUNC('week', DATEADD('week', -12, CURRENT_DATE))
	WHERE dc.status = 'Ativo'
	GROUP BY 1, 2
),
visits_completed AS (
  SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_listing_rent_flows.sk_region,
    COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_booking  >= 0) AND (fact_listing_rent_flows.flg_visit_completed  > 0) THEN fact_listing_rent_flows.sk_booking  ELSE NULL END) AS visits_completed
  FROM public.fact_listing_rent_flows AS fact_listing_rent_flows
  JOIN public.dim_date ON fact_listing_rent_flows.sk_booking_created_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
  GROUP BY 1, 2
),
offers_submitted AS (
  SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_listing_rent_flows.sk_region,
    COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_offer_submitted_date  >= 0) THEN fact_listing_rent_flows.sk_offer  ELSE NULL END) AS offers_submitted
  FROM public.fact_listing_rent_flows AS fact_listing_rent_flows
  JOIN public.dim_date ON fact_listing_rent_flows.sk_offer_submitted_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
  GROUP BY 1, 2
),
prospects AS (
	SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_house_listing_flows.sk_region,
		COUNT(CASE WHEN (fact_house_listing_flows.sk_prospect_date  >= 0) THEN 1 ELSE NULL END) AS prospects
	FROM public.fact_house_listing_flows AS fact_house_listing_flows
	JOIN public.dim_date ON fact_house_listing_flows.sk_prospect_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
	GROUP BY 1, 2
),
first_listings AS (
	SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_house_listing_flows.sk_region,
		COUNT(CASE WHEN (fact_house_listing_flows.sk_first_listing_date  >= 0) THEN 1 ELSE NULL END) AS first_listings
	FROM public.fact_house_listing_flows AS fact_house_listing_flows
	JOIN public.dim_date ON fact_house_listing_flows.sk_first_listing_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
	GROUP BY 1, 2
),
online_metrics AS (
  with amplitude as (
  SELECT
  	DATE_TRUNC('week', CAST(SUBSTRING(event_time, 1, 10) AS DATE)) AS event_date,
  	TRIM(evt.e_house_id) AS house_id,
    CASE WHEN TRIM(evt.et) = 'listing_page_viewed' THEN evt.uuid END AS listing_page_views,
    CASE WHEN TRIM(evt.et) = 'schedule_page_viewed' THEN evt.uuid END AS schedule_page_views
  FROM datalake_clean.amplitude_events evt
  	WHERE TRIM(evt.et) IN ('listing_page_viewed', 'schedule_page_viewed')
  	AND TRIM(app) = '170698'
  	AND ym >= '2019-05'
  union
  -- enriching with amplitude data via SPARK
   SELECT
  	DATE_TRUNC('week', CAST(SUBSTRING(event_time, 1, 10) AS DATE)) AS event_date,
  	cast(json_extract_path_text(event_properties, 'house_id') as varchar) AS house_id,
    CASE WHEN event_type = 'listing_page_viewed' THEN uuid END AS listing_page_views,
    CASE WHEN event_type = 'schedule_page_viewed' THEN uuid END AS schedule_page_views
   FROM datalake_clean_spark.amplitude_events
  	WHERE event_type IN ('listing_page_viewed', 'schedule_page_viewed')
  	AND app = 170698
  	AND year >= 2019
  )
  select
   event_date,
   house_id,
   count(distinct listing_page_views) as listing_page_views,
   count(distinct schedule_page_views) as schedule_page_views
  from amplitude
  group by 1, 2
),
houses AS (
  SELECT DISTINCT
      SUBSTRING(lf.sk_house_listing, 1, 9) AS house_id,
      lf.sk_region
  FROM public.fact_house_listing_flows lf
  WHERE lf.sk_house_listing > 0
),
online_metrics_by_region AS (
  SELECT
		DATE_TRUNC('week', om.event_date) AS date_period,
    h.sk_region,
    SUM(listing_page_views) AS listing_page_views,
    SUM(schedule_page_views) AS schedule_page_views
  FROM online_metrics om
  JOIN houses h ON om.house_id = h.house_id
  WHERE event_date >= DATE_ADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', event_date) = DATE_TRUNC('week', CURRENT_DATE)
  GROUP BY 1, 2
)
SELECT metrics.*,
			 region.name,
			 region.city_name,
			 region.city_group,
			 region.region_code,
			 region.regional
FROM
(
  SELECT *
  FROM contracts_signed
  FULL OUTER JOIN visits_booked USING(date_period, sk_region)
  FULL OUTER JOIN ongoing_listings USING(date_period, sk_region)
  FULL OUTER JOIN ongoing_rentals USING(date_period, sk_region)
  FULL OUTER JOIN visits_completed USING(date_period, sk_region)
  FULL OUTER JOIN offers_submitted USING(date_period, sk_region)
  FULL OUTER JOIN prospects USING(date_period, sk_region)
  FULL OUTER JOIN first_listings USING(date_period, sk_region)
  FULL OUTER JOIN online_metrics_by_region USING(date_period, sk_region)
) metrics
LEFT JOIN public.dim_region region USING(sk_region)
WHERE sk_region != -1
