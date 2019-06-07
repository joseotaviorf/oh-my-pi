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
	LEFT JOIN public.dim_date ON fact_listing_rent_flows.sk_contract_signed_date = dim_date.sk_date
	WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
	GROUP BY 1, 2
),
visits_booked AS (
  SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_listing_rent_flows.sk_region,
  	COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_booking  >= 0) THEN fact_listing_rent_flows.sk_booking  ELSE NULL END) AS visits_booked
	FROM public.fact_listing_rent_flows AS fact_listing_rent_flows
	LEFT JOIN public.dim_date ON fact_listing_rent_flows.sk_booking_created_date = dim_date.sk_date
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
listings_with_visit_booked AS (
	SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    flrf.sk_region,
  	COUNT(DISTINCT CASE WHEN (flrf.sk_booking  >= 0) THEN flrf.sk_house_listing  ELSE NULL END) AS listings_with_visit_booked
	FROM public.fact_listing_rent_flows AS flrf
	LEFT JOIN public.dim_date ON flrf.sk_booking_created_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
	GROUP BY 1, 2
),
visits_completed AS (
  SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_listing_rent_flows.sk_region,
    COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_booking  >= 0) AND (fact_listing_rent_flows.flg_visit_completed  > 0) THEN fact_listing_rent_flows.sk_booking  ELSE NULL END) AS visits_completed
  FROM public.fact_listing_rent_flows AS fact_listing_rent_flows
  LEFT JOIN public.dim_date ON fact_listing_rent_flows.sk_booking_created_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
  GROUP BY 1, 2
),
offers_submitted AS (
  SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_listing_rent_flows.sk_region,
    COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_offer_submitted_date  >= 0) THEN fact_listing_rent_flows.sk_offer  ELSE NULL END) AS offers_submitted
  FROM public.fact_listing_rent_flows AS fact_listing_rent_flows
  LEFT JOIN public.dim_date ON fact_listing_rent_flows.sk_offer_submitted_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
  GROUP BY 1, 2
),
listings_with_offer_submitted AS (
  SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_listing_rent_flows.sk_region,
    COUNT(DISTINCT CASE WHEN (fact_listing_rent_flows.sk_offer_submitted_date  >= 0) THEN fact_listing_rent_flows.sk_house_listing  ELSE NULL END) AS listings_with_offer_submitted
  FROM public.fact_listing_rent_flows AS fact_listing_rent_flows
  LEFT JOIN public.dim_date ON fact_listing_rent_flows.sk_offer_submitted_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
  GROUP BY 1, 2
),
prospects AS (
	SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_house_listing_flows.sk_region,
		COUNT(CASE WHEN (fact_house_listing_flows.sk_prospect_date  >= 0) THEN 1 ELSE NULL END) AS prospects
	FROM public.fact_house_listing_flows AS fact_house_listing_flows
	LEFT JOIN public.dim_date ON fact_house_listing_flows.sk_prospect_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
	GROUP BY 1, 2
),
first_listings AS (
	SELECT
    DATE_TRUNC('week', dim_date.date) AS date_period,
    fact_house_listing_flows.sk_region,
		COUNT(CASE WHEN (fact_house_listing_flows.sk_first_listing_date  >= 0) THEN 1 ELSE NULL END) AS first_listings
	FROM public.fact_house_listing_flows AS fact_house_listing_flows
	LEFT JOIN public.dim_date ON fact_house_listing_flows.sk_first_listing_date = dim_date.sk_date
  WHERE dim_date.date >= DATEADD('week', -12, CURRENT_DATE) OR DATE_TRUNC('week', dim_date.date) = DATE_TRUNC('week', CURRENT_DATE)
	GROUP BY 1, 2
)
SELECT metrics.*,
			 region.name,
			 region.city_name,
			 region.city_group,
			 region.region_code,
			 CASE
			     WHEN region.city_group IN ('Belo Horizonte', 'Brasília', 'Goiânia', 'Campinas') THEN 'Center'
			     WHEN region.city_group IN ('RMSP') THEN 'RMSP'
					 WHEN region.city_group IN ('Rio de Janeiro', 'Curitiba', 'Florianópolis', 'Porto Alegre') THEN 'RJ / South'
					 ELSE 'No regional'
			 END AS regional
FROM
(
  SELECT *
  FROM contracts_signed
  JOIN visits_booked USING(date_period, sk_region)
	JOIN listings_with_visit_booked USING(date_period, sk_region)
  JOIN ongoing_listings USING(date_period, sk_region)
  JOIN visits_completed USING(date_period, sk_region)
  JOIN offers_submitted USING(date_period, sk_region)
	JOIN listings_with_offer_submitted USING(date_period, sk_region)
  JOIN prospects USING(date_period, sk_region)
  JOIN first_listings USING(date_period, sk_region)
) metrics
LEFT JOIN public.dim_region region USING(sk_region)
WHERE sk_region != -1
