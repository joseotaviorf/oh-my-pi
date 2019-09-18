    WITH
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
    metrics AS (
      SELECT
        *
      FROM visits_booked vb
      FULL OUTER JOIN visits_completed vc USING(date_period, sk_house_listing)
    )
    SELECT
      DATE_TRUNC('week', d.date_day) AS date_period,
      m.sk_house_listing,
      m.visits_booked,
      m.visits_completed
    FROM dates d
    LEFT JOIN metrics m ON m.date_period = DATE_TRUNC('week', d.date_day)
