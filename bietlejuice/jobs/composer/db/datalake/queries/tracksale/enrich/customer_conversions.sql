WITH unnested_dispatches AS (
	SELECT
		id AS id_dispatch,
		EXPLODE(FROM_JSON(customers,'array<string>')) AS customer
	FROM datalake_tracksale.dispatch
),
clean_unnested_dispatches AS (
	SELECT
		id_dispatch,
		LOWER(GET_JSON_OBJECT(customer,'$.name')) AS customer_name,
		LOWER(GET_JSON_OBJECT(customer,'$.email')) AS customer_email,
		REGEXP_REPLACE(REGEXP_REPLACE(GET_JSON_OBJECT(customer,'$.phone'),'\\D+',''),'^55','') AS customer_phone
	FROM unnested_dispatches
),
dispatch_customers AS (
	SELECT
		id_dispatch,
		customer_name,
		customer_email,
		customer_phone,
		IF(CONCAT(
                  COALESCE(customer_email,''),
                  COALESCE(customer_phone,''),
                  COALESCE(customer_name,'')
                  ),'','-1') AS id_customer
	FROM clean_unnested_dispatches
	GROUP BY 1,2,3,4,5
),
answers AS (
	SELECT
		id AS id_answer,
		lot_code AS id_dispatch,
		IF(CONCAT(
                  COALESCE(LOWER(email),''),
                  COALESCE(REGEXP_REPLACE(phone,'\\D+',''),''),
                  COALESCE(LOWER(name),'')
                  ),'','-1') AS id_customer,
		email,
		phone
	FROM datalake_tracksale.answer
),
-- consider only the last answer for each customer in a dispatch that was identified
last_dispatch_answers AS (
	SELECT
		id_dispatch,
		id_customer,
		MAX(id_answer) AS id_last_answer
	FROM answers
	WHERE id_customer != '-1'
	GROUP BY 1,2
),
answer_customers AS (
	SELECT
		a.id_answer,
		a.id_dispatch,
		a.id_customer
	FROM answers a
	INNER JOIN last_dispatch_answers lda
		ON lda.id_last_answer = a.id_answer
),
-- union last answer from identified costumers and answers from not identified customers
all_answers AS (
	SELECT * FROM answer_customers
    	UNION ALL
    	SELECT 
              id_answer,
              id_dispatch,
              id_customer
    	FROM answers
    	WHERE id_customer = '-1'
)
SELECT
	CONCAT(
		dc.id_dispatch,
		COALESCE(dc.id_customer,CAST(ac.id_answer AS STRING))
		) AS id_dispatch,
	COALESCE(dc.id_dispatch,d.id) AS id_dispatch_lot,
	dc.id_customer,
	dc.customer_email,
	dc.customer_phone,
	ac.id_answer,
	dc.id_customer != '' AS is_customer_identified
FROM answer_customers ac
FULL JOIN dispatch_customers dc
	ON dc.id_dispatch = ac.id_dispatch
	AND dc.id_customer = ac.id_customer
LEFT JOIN datalake_tracksale.dispatch d -- complete dispatch information in answers that could not relate to dispatches
	ON d.id = ac.id_dispatch
	AND dc.id_dispatch IS NULL
	AND dc.id_customer IS NULL
