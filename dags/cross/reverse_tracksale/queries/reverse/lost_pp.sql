WITH unpublished_listings AS (
	SELECT
		sk_house_listing,
		CASE
			WHEN status_history IN ('despublicado','UNPUBLISHED') THEN 'despublicado'
			WHEN status_history IN ('publicado','PUBLISHED') THEN 'publicado'
			WHEN status_history = 'alugado'
				OR (status_history = 'SUSPENDED' AND status_change_reason = 'RENTED') THEN 'alugado'
			ELSE status_history
		END AS status_history2,
		ts_status_start,
		ts_status_end
	FROM
		dw_rent.fact_house_listing_status
	WHERE
		country_code = 'BR'
		AND is_last_status_of_day = true
),
unpublished AS (
	SELECT
		sk_house_listing,
		MIN(DATE(ts_status_start)) AS dt_min_unpublished
	FROM
		unpublished_listings
	WHERE
		status_history2 = 'despublicado'
	GROUP BY 1
),
listing_aux AS (
	SELECT
		u.sk_house_listing,
		DATE(u.ts_status_start) AS dt_status_started,
		IF(u.status_history2 IN ('publicado','alugado'), 'publicado/alugado', u.status_history2) AS status_history2,
		ROW_NUMBER() OVER (PARTITION BY u.sk_house_listing, DATE(u.ts_status_start) ORDER BY u.ts_status_end DESC) AS rn
	FROM
		unpublished_listings AS u
	INNER JOIN
		unpublished AS unp
			ON unp.sk_house_listing = u.sk_house_listing
	INNER JOIN
		dw_rent.dim_house_listing AS dhl
			ON dhl.sk_house_listing = u.sk_house_listing
	WHERE
		DATE(u.ts_status_start) >= unp.dt_min_unpublished
		AND u.status_history2 IN ('publicado', 'alugado', 'despublicado')
		AND dhl.version <> 0
),
listing_aux2 as (
	SELECT
		sk_house_listing,
		status_history2 AS current_event_status,
		dt_status_started AS dt_current_event,
		DATE_ADD(dt_status_started, 90) AS dt_ended,
		LEAD(dt_status_started, 1) OVER (PARTITION BY sk_house_listing ORDER BY dt_status_started) AS dt_next_event
	FROM
		listing_aux
	WHERE
		rn = 1
),
crisis_users AS (
	SELECT DISTINCT
        ft.sk_user
    FROM
        dw_customer_support.fact_tickets AS ft
    INNER JOIN
        dw_customer_support.dim_ticket AS dt
        	ON dt.sk_ticket = ft.sk_ticket
    INNER JOIN
        dw_customer_support.dim_department AS dd
        	ON dd.department = dt.group_name
    WHERE
        (
			dt.group_name IN (
				'Notificação Extrajudicial [CE] [POS] [BACK]',
				'Dados Bancários [CE] [POS] [BACK]',
				'CX ReclameAqui Adquiridas [CE] [POS] [BACK]'
			) OR dd.team IN ('Casos Especiais', 'Ouvidoria', 'ReclameAqui', 'Evictions')
        )
        AND ft.sk_user <> -1
        AND ft.ts_solved IS NULL
),
base AS (
	SELECT
		sk_house_listing,
		dt_current_event,
		current_event_status,
		CASE
			WHEN dt_next_event IS NULL THEN FALSE
			WHEN dt_next_event > dt_ended THEN FALSE
			ELSE TRUE
		END AS has_next_event
	FROM
		listing_aux2
)
SELECT
	du.nome AS customer_name,
	du.email AS customer_email,
	du.telefone_principal AS customer_phone,
	'PP Lost' AS campaign_step,
	'Proprietário' AS customer_type,
	du.cpf AS customer_cpf,
	h.id_user AS id_user,
	'lost' AS campaign_type,
	'house_listing' AS driver_type,
	b.sk_house_listing AS id_driver,
	NOW() AS ts_load
FROM
	base AS b
JOIN
	dw_rent.dim_house_listing AS dhl
		ON dhl.sk_house_listing = b.sk_house_listing
JOIN
	datalake_ebdb_clean.house AS h
		ON h.id = dhl.id_house
JOIN
	dw_public.dim_user AS du
		ON du.sk_user = h.id_user
LEFT JOIN
	datalake_ebdb_clean.user_pro_owner AS po
		ON po.id_user = h.id_user
LEFT JOIN
	crisis_users AS cu
		ON cu.sk_user = h.id_user
WHERE
	dhl.country_code = 'BR'
	AND DATEDIFF(CURRENT_DATE, b.dt_current_event) = 4
	AND b.has_next_event IS FALSE
	AND b.current_event_status = 'despublicado'
	AND dhl.rental_administrator = 'QUINTOANDAR'
	AND dhl.is_for_sale IS FALSE
	AND dhl.is_b2b IS false
	AND cu.sk_user IS NULL -- no crisis users
	AND po.id_user IS NULL -- no Pro-Owners
UNION ALL
SELECT
	'Teste Disparo' AS customer_name,
	'testes.disparos.5a@gmail.com' AS customer_email,
	'+5511123456789' AS customer_phone,
	'PP Lost' AS campaign_step,
	'Proprietário' AS customer_type,
	'1234' AS customer_cpf,
	'1234' AS id_user,
	'lost' AS campaign_type,
	'house_listing' AS driver_type,
	'1234' AS id_driver,
	NOW() AS ts_load
