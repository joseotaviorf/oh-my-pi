WITH dispatches AS (
	SELECT
		id AS id_dispatch,
		customers,
		CONCAT(
			CAST(year AS STRING),
			LPAD(CAST(month AS STRING), 2, '0'),
			LPAD(CAST(day AS STRING), 2, '0')
			) AS dt_updated
	FROM datalake_tracksale_clean.dispatch
),
last_updated_dispatches AS (
	SELECT
		id_dispatch,
		MAX(dt_updated) AS dt_last_updated
	FROM dispatches
	GROUP BY 1
),
unnested_dispatches AS (
	SELECT
		d.id_dispatch,
		EXPLODE(FROM_JSON(d.customers,'array<string>')) as customer
	FROM dispatches d
	INNER JOIN last_updated_dispatches lud
		ON lud.id_dispatch = d.id_dispatch
		AND lud.dt_last_updated = d.dt_updated
),
clean_unnested_dispatches AS (
	SELECT
		id_dispatch,
		LOWER(GET_JSON_OBJECT(customer,'$.name')) AS customer_name,
		GET_JSON_OBJECT(customer,'$.email') AS customer_email,
		REGEXP_REPLACE(REGEXP_REPLACE(GET_JSON_OBJECT(customer,'$.phone'),'\\D+',''),'^55','') AS customer_phone
	FROM unnested_dispatches
),
dispatch_customers AS (
	SELECT
		id_dispatch,
		customer_name,
		customer_email,
		customer_phone,
		CONCAT(
			COALESCE(customer_email,''),
			COALESCE(customer_phone,''),
			COALESCE(customer_name,'')
			) AS id_customer
	FROM clean_unnested_dispatches
	GROUP BY 1,2,3,4,5
),
answers AS (
	SELECT
		a.id AS id_answer,
		a.lot_code AS id_dispatch,
		a.name,
		a.email,
		REGEXP_REPLACE(a.phone,'\\D+','') AS phone,
		a.tags,
		CONCAT(
			CAST(a.year AS STRING),
			LPAD(CAST(a.month AS STRING), 2, '0'),
			LPAD(CAST(a.day AS STRING), 2, '0')
			) AS dt_updated
	FROM datalake_tracksale_clean.answer a
),
last_updated_answers AS (
	SELECT
		id_answer,
		MAX(dt_updated) AS dt_last_updated
	FROM answers
	GROUP BY 1
),
unique_answers AS (
	SELECT
		a.id_answer,
		a.id_dispatch,
		CONCAT(
			COALESCE(a.email,''),
			COALESCE(a.phone,''),
			COALESCE(LOWER(a.name),'')
			) AS id_customer,
		a.email,
		a.phone
	FROM answers a
	INNER JOIN last_updated_answers lua
		ON lua.id_answer = a.id_answer
		AND lua.dt_last_updated = a.dt_updated
),
-- consider only the last answer for each customer in a dispatch
last_dispatch_answers AS (
	SELECT
		id_dispatch,
		id_customer,
		MAX(id_answer) AS id_last_answer
	FROM unique_answers
	GROUP BY 1,2
),
answer_customers AS (
	SELECT
		ua.id_answer,
		ua.id_dispatch,
		ua.id_customer
	FROM unique_answers ua
	INNER JOIN last_dispatch_answers lda
	ON lda.id_last_answer = ua.id_answer
)
SELECT
	CONCAT(
		dc.id_dispatch,
		COALESCE(dc.id_customer,CAST(ac.id_answer AS STRING))
		) AS id_dispatch,
	COALESCE(dc.id_dispatch,d.id_dispatch) AS id_dispatch_lot,
	dc.id_customer,
	dc.customer_email,
	dc.customer_phone,
	ac.id_answer
FROM answer_customers ac
FULL JOIN dispatch_customers dc
	ON dc.id_dispatch = ac.id_dispatch
	AND dc.id_customer = ac.id_customer
	AND ac.id_customer != '' -- avoid a cartesian product in id_customer of empty string
LEFT JOIN dispatches d -- complete dispatch information in answers that could not relate to dispatches
	ON d.id_dispatch = ac.id_dispatch
	AND dc.id_dispatch IS NULL
	AND dc.id_customer IS NULL
