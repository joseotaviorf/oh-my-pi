-- Benvi IQ Lost Visitas: visitors with rent bookings on D-10 which did neither send an offer nor book another visit after that
WITH mex_houses AS (
    SELECT
        DISTINCT sk_house_listing
    FROM
		dw_rent.dim_house_listing
    WHERE
		country_code = 'MX' --- added to filter only MX business (excluding BR)
),
distinct_bookings AS (
	SELECT
		rf.sk_client,
		rf.sk_house_listing,
		rf.sk_booking,
		rf.sk_booking_created_date
	FROM
		dw_rent.fact_listing_rent_flows AS rf
	INNER JOIN
		mex_houses h
			ON rf.sk_house_listing = h.sk_house_listing  --- added to filter only MX business (excluding BR)
	WHERE
		rf.sk_booking > 0
	GROUP BY 1, 2, 3, 4
),
-- consider the first booking on D-4 for each visitor
first_booking AS (
	SELECT
		sk_client,
		MIN(sk_booking) AS first_sk_booking -- id because there could be n bookings in a day
	FROM
		distinct_bookings
	GROUP BY 1
),
-- get the next booking for each client and booking
next_bookings AS (
	SELECT
		sk_client,
		sk_house_listing,
		sk_booking,
		sk_booking_created_date,
		LEAD(sk_booking,1) OVER (PARTITION BY sk_client ORDER BY sk_booking) AS next_sk_booking -- next booking will have a greater id (incremental)
	FROM
		distinct_bookings
),
-- considering only the city of the first booking for each client
first_booking_city AS (
	SELECT
		nb.*
	FROM
		next_bookings AS nb
	INNER JOIN
		first_booking AS fb
			ON nb.sk_booking = fb.first_sk_booking
),
-- get all distinct offers sent for each client
distinct_offers AS (
	SELECT
		sk_client,
		sk_offer,
		sk_offer_submitted_date
	FROM
		dw_rent.fact_listing_rent_flows
	GROUP BY 1, 2, 3
),
-- get all distinct talk to agent for each client
distinct_talk_to_agent AS (
	SELECT
		tenant_id AS sk_client,
	    sk_house_listing,
	    house_id,
	    CONCAT(CONCAT(house_id, tenant_id), agent_id) AS sk_tta,
		sk_date AS sk_first_message
	FROM
		datalake_talk_to_agent.talk_to_agent AS tta
	INNER JOIN
		dw_public.dim_date AS dd
			ON dd.date = DATE(tta.first_message_ts)
	GROUP BY 1, 2, 3, 4, 5
),
-- consider the first talk to agent for each visitor
first_talk_to_agent AS (
	SELECT
		sk_client,
		MIN(sk_tta) AS first_sk_tta -- id because there could be n bookings in a day
	FROM
		distinct_talk_to_agent
	GROUP BY 1
),
-- get the next talk to agent for each client
next_tta AS (
	SELECT
		sk_client,
		sk_house_listing,
		sk_tta,
		sk_first_message,
		LEAD(sk_tta, 1) OVER (PARTITION BY sk_client ORDER BY sk_tta) AS next_sk_tta -- next talk to agent
	FROM
		distinct_talk_to_agent
),
-- considering only the city of the first talk to agent for each client
first_tta_city AS (
	SELECT
		nb.*
	FROM
		next_tta AS nb
	INNER JOIN
		first_talk_to_agent AS fb
			ON nb.sk_tta = fb.first_sk_tta
),
-- relate next funnel steps (booking -> offer or booking or talk to agent) for each client
next_steps_booking AS (
	SELECT
		fb.sk_client,
		fb.sk_house_listing,
		dd.date AS dt_booking,
		fb.sk_booking,
		fb.next_sk_booking,
		od.sk_offer AS next_sk_offer,
		tta.sk_tta AS next_tta
	FROM
		first_booking_city AS fb
	INNER JOIN
		dw_public.dim_date AS dd
			ON dd.sk_date = fb.sk_booking_created_date
	LEFT JOIN
		distinct_offers AS od
			ON od.sk_client = fb.sk_client
			AND od.sk_offer_submitted_date >= fb.sk_booking_created_date -- consider offers submitted only after visit
			AND od.sk_offer > 0 -- selecting only valid offer registers
	LEFT JOIN
		distinct_talk_to_agent tta
			ON tta.sk_client = fb.sk_client
			AND tta.sk_first_message >= fb.sk_booking_created_date
			AND tta.sk_tta IS NOT NULL
),
-- relate next funnel steps (talk to agent -> offer or booking or talk to agent) for each client
next_steps_tta AS (
	SELECT
		tta.sk_client,
		tta.sk_house_listing,
		dd.date AS dt_talk_to_agent,
		tta.sk_tta,
		tta.next_sk_tta,
		od.sk_offer AS next_sk_offer,
		db.sk_booking AS next_sk_booking
	FROM
		first_tta_city AS tta
	INNER JOIN
		dw_public.dim_date AS dd
			ON dd.sk_date = tta.sk_first_message
	LEFT JOIN
		distinct_offers AS od
			ON od.sk_client = tta.sk_client
			AND od.sk_offer_submitted_date >= tta.sk_first_message -- consider offers submitted only after visit
			AND od.sk_offer > 0 -- selecting only valid offer registers
	LEFT JOIN
		distinct_bookings AS db
			ON tta.sk_client = db.sk_client
			AND db.sk_booking_created_date >= tta.sk_first_message
			AND db.sk_booking > 0
),
-- filter visitors with NPS conditions
visitors AS (
	SELECT
		ns.sk_client,
		ns.sk_booking
	FROM
		next_steps_booking AS ns
	INNER JOIN
		dw_rent.dim_house_listing AS dhl
	    	ON dhl.sk_house_listing = ns.sk_house_listing
			AND dhl.country_code = 'MX'
	LEFT JOIN
		datalake_ebdb_clean.house AS h
	    	ON h.id = dhl.id_house
	WHERE
		ns.dt_booking = DATE_ADD(CURRENT_DATE(), -10) -- SELECT the initial booking on D-10
		AND ns.next_sk_booking IS NULL -- selecting visitors without a next booking
		AND ns.next_sk_offer IS NULL -- selecting visitors without a next offer
		AND ns.next_tta IS NULL -- selecting visitors without a next talk to agent
		AND h.id_user <> ns.sk_client -- excluding visitors who has visited their own house
		AND dhl.short_id_house NOT IN ('718594','718599','718602','718607') -- properties of nalata marketing action, with visits booked through the usual process
	GROUP BY 1, 2
),
-- filter talk to agent NPS conditions
visitors_tta AS (
	SELECT
		ns.sk_client,
		ns.sk_tta
	FROM
		next_steps_tta AS ns
	INNER JOIN
		dw_rent.dim_house_listing AS dhl
	    	ON dhl.sk_house_listing = ns.sk_house_listing
			AND dhl.country_code = 'MX'
	LEFT JOIN
		datalake_ebdb_clean.house AS h
	    	ON h.id = dhl.id_house
	WHERE
		ns.dt_talk_to_agent = DATE_ADD(CURRENT_DATE(), -10) -- SELECT the initial booking on D-10
		AND ns.next_sk_booking IS NULL -- selecting visitors without a next booking
		AND ns.next_sk_offer IS NULL -- selecting visitors without a next offer
		AND ns.next_sk_tta IS NULL -- selecting visitors without a next talk to agent
		AND h.id_user <> ns.sk_client -- excluding visitors who has visited their own house
		AND dhl.short_id_house NOT IN ('718594','718599','718602','718607') -- properties of nalata marketing action, with visits booked through the usual process
	GROUP BY 1, 2
)
SELECT
	u.nome AS customer_name,
	u.email AS customer_email,
	u.telefone_principal AS customer_phone,
	'Visita' AS campaign_step,
	'Inquilino' AS customer_type,
	u.cpf AS customer_cpf,
	u.sk_user AS id_user,
	'lost' AS campaign_type,
	'booking' AS driver_type,
	cast(v.sk_booking AS char(7)) AS id_driver,
	NOW() AS ts_load
FROM
	visitors AS v
INNER JOIN
	dw_public.dim_user AS u
		ON u.sk_user = v.sk_client
UNION
SELECT
	u.nome AS customer_name,
	u.email AS customer_email,
	u.telefone_principal AS customer_phone,
	'Visita' AS campaign_step,
	'Inquilino' AS customer_type,
	u.cpf AS customer_cpf,
	u.sk_user AS id_user,
	'lost' AS campaign_type,
	'talk to agent' AS driver_type,
	vt.sk_tta AS id_driver,
	NOW() AS ts_load
FROM
	visitors_tta vt
INNER JOIN
	dw_public.dim_user AS u
		ON u.sk_user = vt.sk_client
UNION ALL
SELECT
	'Teste Disparo' AS customer_name,
	'testes.disparos.5a@gmail.com' AS customer_email,
	'5511123456789' AS customer_phone,
	'Visita' AS campaign_step,
	'Inquilino' AS customer_type,
	'1234' AS customer_cpf,
	'1234' AS id_user,
	'lost' AS campaign_type,
	'booking' AS driver_type,
	'1234' AS id_driver,
	NOW() AS ts_load
