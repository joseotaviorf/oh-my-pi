WITH brazil_houses AS (
	SELECT
		DISTINCT sk_house_listing
	FROM
		dw_public.dim_house_listing
	WHERE
		country_code = 'BR'
),
distinct_bookings AS (
	SELECT
		rf.sk_client,
		rf.sk_house_listing,
		rf.sk_booking,
		rf.sk_booking_created_date
	FROM
		dw_public.fact_listing_rent_flows rf
    INNER JOIN
        brazil_houses h
			ON rf.sk_house_listing = h.sk_house_listing
	WHERE
		rf.sk_booking > 0
	GROUP BY 1,2,3,4
),
first_booking AS (
	SELECT
		sk_client,
		min(sk_booking) AS first_sk_booking
	FROM
		distinct_bookings
	GROUP BY 1
),
next_bookings AS (
	SELECT
		sk_client,
		sk_house_listing,
		sk_booking,
		sk_booking_created_date,
		lead(sk_booking,1) OVER (PARTITION BY sk_client ORDER BY sk_booking) AS next_sk_booking
	FROM
		distinct_bookings
),
first_booking_city AS (
	SELECT
		nb.*
	FROM
		next_bookings nb
	INNER JOIN
		first_booking fb
			ON nb.sk_booking = fb.first_sk_booking
),
distinct_offers AS (
	SELECT
		sk_client,
		sk_offer,
		sk_offer_submitted_date
	FROM
		dw_public.fact_listing_rent_flows
	GROUP BY 1,2,3
),
distinct_talk_to_agent AS (
	SELECT tenant_id AS sk_client,
	       sk_house_listing,
	       house_id,
	       CONCAT(CONCAT(house_id, tenant_id), agent_id) AS sk_tta,
	       sk_date AS sk_first_message
	FROM
		dw_datamarts_cross.talk_to_agent tta
	INNER JOIN
		dw_public.dim_date dd
			ON dd.date = DATE(tta.first_message_ts)
	GROUP BY 1, 2, 3, 4, 5
),
first_talk_to_agent AS (
	SELECT
		sk_client,
		MIN(sk_tta) AS first_sk_tta
	FROM
		distinct_talk_to_agent
	GROUP BY 1
),
next_tta AS (
	SELECT
		sk_client,
		sk_house_listing,
		sk_tta,
		sk_first_message,
		LEAD(sk_tta,1) OVER (PARTITION BY sk_client ORDER BY sk_tta) AS next_sk_tta
	FROM
		distinct_talk_to_agent
),
first_tta_city AS (
	SELECT
		nb.*
	FROM
		next_tta nb
	INNER JOIN
		first_talk_to_agent fb
			ON nb.sk_tta = fb.first_sk_tta
),
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
		first_booking_city fb
	INNER JOIN
		dw_public.dim_date dd
			ON dd.sk_date = fb.sk_booking_created_date
	LEFT JOIN
		distinct_offers od
			ON od.sk_client = fb.sk_client
			AND od.sk_offer_submitted_date >= fb.sk_booking_created_date
			AND od.sk_offer > 0
	LEFT JOIN
		distinct_talk_to_agent tta
			ON tta.sk_client = fb.sk_client
			AND tta.sk_first_message >= fb.sk_booking_created_date
			AND tta.sk_tta IS NOT NULL
),
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
		first_tta_city tta
	INNER JOIN
		dw_public.dim_date dd
			ON dd.sk_date = tta.sk_first_message
	LEFT JOIN
		distinct_offers od
			ON od.sk_client = tta.sk_client
			AND od.sk_offer_submitted_date >= tta.sk_first_message
			AND od.sk_offer > 0
	LEFT JOIN
		distinct_bookings db
			ON tta.sk_client = db.sk_client
			AND db.sk_booking_created_date >= tta.sk_first_message
			AND db.sk_booking > 0
),
visitors AS (
	SELECT
		ns.sk_client,
		ns.sk_booking
	FROM
		next_steps_booking ns
	INNER JOIN
		dw_public.dim_house_listing dhl
			ON dhl.sk_house_listing = ns.sk_house_listing
	LEFT JOIN
		datalake_ebdb_clean.house h
			ON h.id = dhl.id_house
    WHERE
		ns.dt_booking = DATE_ADD(current_date,-10)
		AND ns.next_sk_booking IS NULL
		AND ns.next_sk_offer IS NULL
		AND ns.next_tta IS NULL
		AND h.id_user <> ns.sk_client
		AND dhl.short_id_house NOT IN ('718594','718599','718602','718607')
		AND dhl.country_code = 'BR'
	GROUP BY 1,2
),
visitors_tta AS (
	SELECT
		ns.sk_client,
		ns.sk_tta
	FROM
		next_steps_tta ns
	INNER JOIN
		dw_public.dim_house_listing  dhl
			ON dhl.sk_house_listing = ns.sk_house_listing
	LEFT JOIN
		datalake_ebdb_clean.house h
			ON h.id = dhl.id_house
    WHERE
		ns.dt_talk_to_agent = DATE_ADD(current_date,-10)
		AND ns.next_sk_booking IS NULL
		AND ns.next_sk_offer IS NULL
		AND ns.next_sk_tta IS NULL
		AND h.id_user <> ns.sk_client
		AND dhl.short_id_house NOT IN ('718594','718599','718602','718607')
		AND dhl.country_code = 'BR'
	GROUP BY 1,2
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
	CAST(v.sk_booking AS CHAR(7)) AS id_driver,
    NOW() AS ts_load
FROM
	visitors v
INNER JOIN
	dw_public.dim_user u
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
	dw_public.dim_user u
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