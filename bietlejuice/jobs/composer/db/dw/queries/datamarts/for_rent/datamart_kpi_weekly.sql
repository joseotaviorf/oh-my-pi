WITH ongoing_contracts_weekly AS (
	SELECT
		dd.week_start,
		hl.sk_region,
		COUNT(DISTINCT dc.sk_contract) AS ongoing_contracts_weekly
	FROM
		dim_contract AS dc
	JOIN
		dim_date AS dd
		ON dd.date BETWEEN DATE(COALESCE(COALESCE(dc.ts_signature,dc.dt_start),dc.dt_entrance)) AND (COALESCE(dc.dt_annulment, CURRENT_DATE) - 1)
	LEFT JOIN
		fact_house_listings AS hl
		ON dc.sk_contract = hl.sk_contract
	WHERE
		dd.date < CURRENT_DATE -- we know we may have future dates for dt_annulment AND we need to filter future dates
		AND dc.status IN ('Ativo','Finalizado') -- consider only contracts that are active or were active AND ended
		AND dd.weekday_name = 'Sunday'
		AND type <> 'DealOnly' -- this type of contract should only be considered for new contracts signed
	GROUP BY 1, 2
),
ongoing_rentals_weekly AS (
	SELECT
		dd.week_start,
		hl.sk_region,
		COUNT(DISTINCT dc.sk_contract) AS ongoing_rentals_weekly
	FROM
		dim_contract AS dc
	JOIN
		dim_date AS dd
		ON dd.date BETWEEN DATE(COALESCE(dc.dt_start, dc.dt_entrance)) 
		AND (COALESCE(dc.dt_annulment, CURRENT_DATE) - INTERVAL '1 day')
	LEFT JOIN
		fact_house_listings AS hl
		ON dc.sk_contract = hl.sk_contract
	WHERE
		dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
		AND dd.weekday_name = 'Sunday' -- only look last day of the week
		AND DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < CURRENT_DATE -- we know we may have future dates for dt_start
		AND dd.date < CURRENT_DATE -- we know we may have future dates for dt_annulment AND we need to filter future dates
		AND type <> 'DealOnly'
	GROUP BY 1, 2
),
new_rentals AS (
	SELECT
		COALESCE(dc.dt_start, dc.dt_entrance) AS rental_date,
		DATE_TRUNC('week',COALESCE(dc.dt_start, dc.dt_entrance)) AS rental_week_start,
		DATE_TRUNC('month',COALESCE(dc.dt_start, dc.dt_entrance)) AS rental_month_start,
		hl.sk_region,
		COUNT(DISTINCT dc.sk_contract) AS new_rentals_daily,
		SUM(COUNT(DISTINCT dc.sk_contract)) OVER(PARTITION BY DATE_TRUNC('week',COALESCE(dc.dt_start, dc.dt_entrance)), hl.sk_region) AS new_rentals_weekly,
		SUM(COUNT(DISTINCT dc.sk_contract)) OVER(PARTITION BY DATE_TRUNC('month',COALESCE(dc.dt_start, dc.dt_entrance)), hl.sk_region) AS new_rentals_monthly
	FROM
		dim_contract AS dc
	LEFT JOIN
		fact_house_listings AS hl
		ON dc.sk_contract = hl.sk_contract
	WHERE
		dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
		AND DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < CURRENT_DATE -- we know we may have future dates for dt_start
		AND (DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < dc.dt_annulment OR dc.dt_annulment IS NULL) -- consider only contracts that weren't annulled before start date
	GROUP BY 1, 2, 3, 4
),
new_contracts AS (
	SELECT
		DATE(COALESCE(dc.ts_signature, dc.dt_start)) AS contract_signed_date,
		DATE_TRUNC('week',COALESCE(dc.ts_signature, dc.dt_start)) AS contract_week_start,
		DATE_TRUNC('month',COALESCE(dc.ts_signature, dc.dt_start)) AS contract_month_start,
		hl.sk_region,
		COUNT(DISTINCT dc.sk_contract) AS new_contracts_signed_daily,
		SUM(COUNT(DISTINCT dc.sk_contract)) OVER(PARTITION BY DATE_TRUNC('week',COALESCE(dc.ts_signature, dc.dt_start)), hl.sk_region) AS new_contracts_signed_weekly,
		SUM(COUNT(DISTINCT dc.sk_contract)) OVER(PARTITION BY DATE_TRUNC('month',COALESCE(dc.ts_signature, dc.dt_start)), hl.sk_region) AS new_contracts_signed_monthly
	FROM 
		dim_contract AS dc
	LEFT JOIN
		fact_house_listings AS hl
		ON dc.sk_contract = hl.sk_contract
	WHERE
		dc.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active AND ended
	GROUP BY 1, 2, 3, 4
),
new_first_listings AS (
SELECT
    dd.date AS first_listing_date,
    DATE_TRUNC('week', dd.date) AS first_listing_week_start,
    DATE_TRUNC('month', dd.date) AS first_listing_month_start,
    lf.sk_region,
    COUNT(DISTINCT lf.sk_house_listing) AS new_first_listings_daily,
    SUM(COUNT(DISTINCT lf.sk_house_listing)) OVER(PARTITION BY DATE_TRUNC('week',dd.date), lf.sk_region) AS new_first_listings_weekly,
    SUM(COUNT(DISTINCT lf.sk_house_listing)) OVER(PARTITION BY DATE_TRUNC('month',dd.date), lf.sk_region) AS new_first_listings_monthly
FROM
	public.fact_house_listing_flows AS lf
JOIN
	dim_date AS dd
	ON lf.sk_first_listing_date = dd.sk_date
	AND dd.date < CURRENT_DATE
WHERE
	lf.sk_first_listing_date > 0
GROUP BY 1, 2, 3, 4
),
re_rentals AS (
	WITH ordered_rentals AS (
		SELECT
			COALESCE(dc.dt_start, dc.dt_entrance) AS rental_date,
			DATE_TRUNC('week',COALESCE(dc.dt_start, dc.dt_entrance)) AS rental_week_start,
			DATE_TRUNC('month',COALESCE(dc.dt_start, dc.dt_entrance)) AS rental_month_start,
			fhl.sk_house_listing,
			fhl.nr_renting,
			dc.status,
			dc.sk_contract,
			ROW_NUMBER() OVER(PARTITION BY dhl.id_house ORDER BY fhl.sk_house_listing) AS row_number_renting,
			fhl.sk_region
		FROM
			dim_contract AS dc
		JOIN
			fact_house_listings AS fhl
			ON dc.sk_contract = fhl.sk_contract
		JOIN
			dim_house_listing AS dhl
			ON dhl.sk_house_listing = fhl.sk_house_listing
		WHERE
			DATE(COALESCE(dc.dt_start, dc.dt_entrance)) < CURRENT_DATE -- we know we may have future dates for dt_start
			AND fhl.nr_renting > 1
	)
	SELECT
		ord.rental_date,
		ord.rental_week_start,
		ord.rental_month_start,
		ord.sk_region,
		COUNT(DISTINCT ord.sk_contract) AS re_rentals_daily,
		SUM(COUNT(DISTINCT ord.sk_contract)) OVER(PARTITION BY DATE_TRUNC('week',ord.rental_week_start), ord.sk_region) AS re_rentals_weekly,
		SUM(COUNT(DISTINCT ord.sk_contract)) OVER(PARTITION BY DATE_TRUNC('month',ord.rental_month_start), ord.sk_region) AS re_rentals_monthly
	FROM
		ordered_rentals AS ord
	WHERE
		ord.row_number_renting > 1 AND ord.status IN ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
	GROUP BY 1, 2, 3, 4
),
ended_rentals AS (
	SELECT
		dc.dt_annulment AS date_date,
		DATE_TRUNC('week',dc.dt_annulment) AS week_date,
		DATE_TRUNC('month',dc.dt_annulment) AS month_date,
		hl.sk_region,
		COUNT(DISTINCT dc.sk_contract) AS ended_rentals_daily,
		SUM(COUNT(DISTINCT dc.sk_contract)) OVER(PARTITION BY DATE_TRUNC('week',dc.dt_annulment), hl.sk_region) AS ended_rentals_weekly,
		SUM(COUNT(DISTINCT dc.sk_contract)) OVER(PARTITION BY DATE_TRUNC('month',dc.dt_annulment), hl.sk_region) AS ended_rentals_monthly
	FROM
		dim_contract AS dc
	LEFT JOIN
		fact_house_listings AS hl
		USING(sk_contract)
	WHERE
		dc.status = 'Finalizado'
		AND dc.dt_annulment < CURRENT_DATE
	GROUP BY 1, 2, 3, 4
),
ended_rentals_confirmed AS (
	SELECT
		DATE(COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)) AS date_date,
		DATE_TRUNC('week',COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)) AS week_date,
		DATE_TRUNC('month',COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)) AS month_date,
		hl.sk_region,
		COUNT(DISTINCT dc.sk_contract) AS ended_rentals_confirmed_daily,
		SUM(COUNT(DISTINCT dc.sk_contract)) OVER(PARTITION BY DATE_TRUNC('week',COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)), hl.sk_region) AS ended_rentals_confirmed_weekly,
		SUM(COUNT(DISTINCT dc.sk_contract)) OVER(PARTITION BY DATE_TRUNC('month',COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)), hl.sk_region) AS ended_rentals_confirmed_monthly
	FROM
		dim_contract AS dc
	LEFT JOIN
		fact_house_listings AS hl
		USING(sk_contract)
	WHERE
		dc.status = 'Finalizado'
		AND COALESCE(ts_analyst_annulment_input,dc.dt_annulment) < CURRENT_DATE
	GROUP BY 1, 2, 3, 4
),
new_bookers AS (
	WITH
	first_booking AS (
		SELECT *
		FROM (
			SELECT
				rf.ods_id,
				rf.sk_client,
				rf.sk_region,
				db.dt_created AS first_booking_created_date,
				ROW_NUMBER() OVER(PARTITION BY rf.sk_client ORDER BY db.dt_created asc) AS rk
			FROM
				fact_listing_rent_flows AS rf
			JOIN 
				dim_booking AS db
				ON db.sk_booking = rf.sk_booking
			WHERE
				rf.sk_booking_created_date
		)
		WHERE rk = 1
		)
	SELECT
		DATE_TRUNC('week',fb.first_booking_created_date) AS first_booking_created_week,
		dr.sk_region,
		COUNT(DISTINCT fb.sk_client) AS new_bookers_weekly
	FROM
		first_booking AS fb
	LEFT JOIN
		fact_listing_rent_flows AS rf
		ON (fb.sk_client = rf.sk_client)
	LEFT JOIN
		dim_date AS dd
		ON rf.sk_contract_signed_date = dd.sk_date
	LEFT JOIN
		dim_region AS dr
		ON fb.sk_region = dr.sk_region
	GROUP BY 1, 2
),
ongoing_listings_weekly AS (
	WITH daily_published_listings AS (
		SELECT
			f.sk_house_listing,
			f.status_history,
			d.date,
			d.week_start,
			d.weekday_name,
			d.month_start,
			d.month_end,
			ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC) AS order_status -- daily order status
		FROM
			fact_house_listing_status AS f
		JOIN 
			dim_date AS d
			ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) 
			AND COALESCE(TO_CHAR(TO_DATE(NULLIF(sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, TO_CHAR(CURRENT_DATE -1, 'YYYYMMDD')::bigint)
		WHERE
			f.status_history = 'publicado' -- consider only published status
			AND SUBSTRING(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
	),
	daily_published_listings_adjusted AS (
		SELECT
			fhs.sk_house_listing,
			fhs.date,
			fhs.week_start,
			fhs.weekday_name,
			fhs.month_start,
			fhs.month_end,
			fhs.order_status,
			fhs.status_history,
			fhl.sk_region
		FROM
			daily_published_listings AS fhs
		LEFT JOIN
			fact_house_listings AS fhl
			ON fhs.sk_house_listing = fhl.sk_house_listing
		LEFT JOIN
			dim_region AS dr
			ON fhl.sk_region = dr.sk_region
		WHERE
			fhs.order_status = 1
			AND dr.city_group IS NOT NULL
			AND fhs.weekday_name = 'Sunday' -- filter that indicates it will be grouped by week
	)
	SELECT
		week_start,
		sk_region,
		COUNT(DISTINCT sk_house_listing) AS ongoing_listings_weekly
	FROM
		daily_published_listings_adjusted
	GROUP BY 1, 2
),
listing_to_contract_signed AS (
	WITH sums AS (
		SELECT
			DATE(DATE_TRUNC('week',dhl.ts_publication)) AS publication_week,
			dr.regional,
			dr.city_group,
			dr.city_name,
			COUNT(DISTINCT dhl.sk_house_listing) AS total_listings,
			COUNT(DISTINCT fhl.sk_contract) AS new_contracts_signed
		FROM
			dim_house_listing AS dhl
		LEFT JOIN
			fact_house_listings AS fhl
			ON fhl.sk_house_listing = dhl.sk_house_listing
		LEFT JOIN
			dim_region AS dr
			ON dr.sk_region = fhl.sk_region
		WHERE
			dhl.ts_publication >= 0
		GROUP BY 1,2,3,4
	)
	SELECT
		publication_week,
		regional,
		city_group,
		city_name,
		new_contracts_signed/total_listings::float AS listing_to_contract_signed_weekly
	FROM sums
),
visits_booked_per_ongoing_listings AS (
	WITH ongoing_listings AS (
		WITH daily_published_listings AS (
			SELECT
				f.sk_house_listing,
				f.status_history,
				d.date,
				d.week_start,
				d.weekday_name,
				d.month_start,
				d.month_end,
				ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start desc) AS order_status -- daily order status
			FROM
				fact_house_listing_status AS f
			JOIN 
				dim_date AS d
				ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) 
				AND COALESCE(TO_CHAR(TO_DATE(NULLIF(sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, TO_CHAR(CURRENT_DATE -1, 'YYYYMMDD')::bigint)
			WHERE
				f.status_history = 'publicado' -- consider only published status
				AND SUBSTRING(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
		),
		daily_published_listings_adjusted AS (
			SELECT
				fhs.sk_house_listing,
				fhs.date,
				fhs.week_start,
				fhs.weekday_name,
				fhs.month_start,
				fhs.month_end,
				fhs.order_status,
				fhs.status_history,
				dr.regional,
				dr.city_group,
				dr.city_name
			FROM
				daily_published_listings AS fhs
			LEFT JOIN
				fact_house_listings AS fhl
				ON fhs.sk_house_listing = fhl.sk_house_listing
			LEFT JOIN
				dim_region AS dr
				ON fhl.sk_region = dr.sk_region
			WHERE
				fhs.order_status = 1
				AND dr.city_group IS NOT NULL
				AND fhs.weekday_name = 'Sunday' -- filter that indicates it will be grouped by week
		)
		SELECT
			week_start,
			regional,
			city_group,
			city_name,
			COUNT(DISTINCT sk_house_listing) AS ongoing_listings
		FROM
			daily_published_listings_adjusted
		GROUP BY 1, 2, 3, 4
	),
	visits_booked AS (
		SELECT
			dd.week_start,
			dr.regional,
			dr.city_group,
			dr.city_name,
			COUNT(DISTINCT CASE WHEN (rf.sk_booking_created_date  > 0) THEN rf.sk_booking ELSE NULL END) AS visits_booked
		FROM
			fact_listing_rent_flows AS rf
		JOIN
			dim_booking AS db
			ON db.sk_booking = rf.sk_booking
		JOIN 
			dim_date AS dd
			ON dd.sk_date = rf.sk_booking_created_date
		LEFT JOIN
			dim_region AS dr
			ON dr.sk_region = rf.sk_region
		WHERE
			dr.city_group IS NOT NULL
		GROUP BY 1, 2, 3, 4
	)
	SELECT
		vb.week_start,
		vb.regional,
		vb.city_group,
		vb.city_name,
		SUM(vb.visits_booked)/SUM(ol.ongoing_listings)::float AS vb_ol
	FROM
		visits_booked AS vb
	LEFT JOIN
		ongoing_listings AS ol
		ON ol.week_start = vb.week_start
		AND ol.city_name = vb.city_name
	WHERE
		vb.week_start IS NOT NULL
	GROUP BY 1,2,3,4
),
weekly_metrics AS (
	SELECT
		DISTINCT COALESCE(ocont.week_start,orent.week_start,nrent.rental_week_start,ncont.contract_week_start,nfl.first_listing_week_start,rr.rental_week_start, er.week_date, erc.week_date, olist.week_start, nbk.first_booking_created_week) AS week_date,
		COALESCE(ocont.sk_region,orent.sk_region,nrent.sk_region,ncont.sk_region,nfl.sk_region,rr.sk_region, er.sk_region, erc.sk_region, olist.sk_region, nbk.sk_region) AS sk_region,
		ocont.ongoing_contracts_weekly,
		orent.ongoing_rentals_weekly,
		nrent.new_rentals_weekly,
		ncont.new_contracts_signed_weekly,
		nfl.new_first_listings_weekly,
		rr.re_rentals_weekly,
		er.ended_rentals_weekly,
		erc.ended_rentals_confirmed_weekly,
		olist.ongoing_listings_weekly,
		nbk.new_bookers_weekly
	FROM
		ongoing_contracts_weekly AS ocont
	FULL OUTER JOIN
		ongoing_rentals_weekly AS orent
		ON ocont.week_start = orent.week_start
		AND ocont.sk_region = orent.sk_region
	FULL OUTER JOIN
		new_rentals AS nrent
		ON ocont.week_start = nrent.rental_week_start
		AND ocont.sk_region = nrent.sk_region
	FULL OUTER JOIN
		new_contracts AS ncont
		ON ocont.week_start = ncont.contract_week_start
		AND ocont.sk_region = ncont.sk_region
	FULL OUTER JOIN
		new_first_listings AS nfl
		ON ocont.week_start = nfl.first_listing_week_start
		AND ocont.sk_region = nfl.sk_region
	FULL OUTER JOIN
		re_rentals AS rr
		ON ocont.week_start = rr.rental_week_start
		AND ocont.sk_region = rr.sk_region
	FULL OUTER JOIN
		ended_rentals AS er
		ON ocont.week_start = er.week_date
		AND ocont.sk_region = er.sk_region
	FULL OUTER JOIN
		ended_rentals_confirmed AS erc
		ON ocont.week_start = erc.week_date
		AND ocont.sk_region = erc.sk_region
	FULL OUTER JOIN
		ongoing_listings_weekly AS olist
		ON ocont.week_start = olist.week_start
		AND ocont.sk_region = olist.sk_region
	FULL OUTER JOIN
		new_bookers AS nbk
		ON ocont.week_start = nbk.first_booking_created_week
		AND ocont.sk_region = nbk.sk_region
),
bookers AS (
	SELECT
		DATE_TRUNC('week',dd.date) AS booking_created_week,
		dr.regional,
		dr.city_group,
		dr.city_name,
		COUNT(DISTINCT rf.sk_client) AS bookers_weekly
	FROM
		fact_listing_rent_flows AS rf
	LEFT JOIN
		dim_date AS dd
		ON rf.sk_booking_created_date = dd.sk_date
	LEFT JOIN
		dim_region AS dr
		ON dr.sk_region = rf.sk_region
	GROUP BY 1, 2, 3, 4
)
SELECT
	DATE(COALESCE(dm.week_date,b.booking_created_week,l2cs.publication_week,vb_ol.week_start)) AS week_date,
	COALESCE(dr.regional,b.regional,l2cs.regional,vb_ol.regional) AS regional,
	COALESCE(dr.city_group,b.city_group,l2cs.city_group,vb_ol.city_group) AS city_group,
	COALESCE(dr.city_name,b.city_name,l2cs.city_name,vb_ol.city_name) AS city_name,
	SUM(dm.ongoing_contracts_weekly) AS ongoing_contracts_weekly,
	SUM(dm.ongoing_rentals_weekly) AS ongoing_rentals_weekly,
	SUM(dm.new_rentals_weekly) AS new_rentals_weekly,
	SUM(dm.new_contracts_signed_weekly) AS new_contracts_signed_weekly,
	SUM(dm.new_first_listings_weekly) AS new_first_listings_weekly,
	SUM(dm.re_rentals_weekly) AS re_rentals_weekly,
	SUM(dm.ended_rentals_weekly) AS ended_rentals_weekly,
	SUM(dm.ended_rentals_confirmed_weekly) AS ended_rentals_confirmed_weekly,
	SUM(dm.ongoing_listings_weekly) AS ongoing_listings_weekly,
	b.bookers_weekly AS bookers_weekly,
	l2cs.listing_to_contract_signed_weekly,
	vb_ol.vb_ol AS visits_booked_per_ongoing_listings_weekly,
	SUM(dm.new_bookers_weekly) AS new_bookers_weekly,
	CURRENT_TIMESTAMP AS ts_load
FROM
	weekly_metrics AS dm
LEFT JOIN
	dim_region AS dr
	USING(sk_region)
FULL OUTER JOIN
	bookers AS b
	ON b.booking_created_week = dm.week_date
	AND dr.city_name = b.city_name
FULL OUTER JOIN
	listing_to_contract_signed AS l2cs
	ON l2cs.publication_week = dm.week_date
	AND dr.city_name = l2cs.city_name
FULL OUTER JOIN
	visits_booked_per_ongoing_listings AS vb_ol
	ON vb_ol.week_start = dm.week_date 
	AND dr.city_name = vb_ol.city_name
GROUP BY 1, 2, 3, 4, 14, 15, 16
