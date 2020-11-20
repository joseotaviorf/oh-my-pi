WITH customer_conversions AS (
	SELECT
		cc.id_customer,
		cc.id_dispatch,
		cc.id_answer,
		d.status,
		a.score_category,
		a.nps_answer,
		a.nps_comment,
		ROUND(a.seconds_spent_answering/60.0,2) AS minutes_spent_answering,
		d.ts_created
	FROM datalake_tracksale.customer_conversions cc
	INNER JOIN datalake_tracksale.dispatch d
		ON cc.id_dispatch_lot = d.id
	LEFT JOIN datalake_tracksale.answer a
		ON cc.id_answer = a.id
	WHERE cc.id_customer != '-1' -- filter out dispatches FROM unidentified customers
),
customer_metrics AS (
	SELECT
		id_customer,
		MAX(id_answer) AS id_last_answer,
		COUNT(id_dispatch) AS total_dispatches,
		COUNT(id_answer) AS total_answers,
		COUNT(CASE WHEN score_category = 'promoter' THEN id_answer end) AS promoters,
		COUNT(CASE WHEN score_category = 'passive' THEN id_answer end) AS passives,
		COUNT(CASE WHEN score_category = 'detractor' THEN id_answer end) AS detractors,
		COUNT(CASE WHEN nps_comment IS NOT NULL THEN id_answer end) AS total_comments,
		AVG(minutes_spent_answering) AS avg_minutes_response_time,
		AVG(nps_answer) AS avg_score,
		COUNT(CASE WHEN status != 'Finalizado' THEN id_dispatch END) > 0 AS has_pending_survey,
		CAST(MAX(ts_created) AS date) AS dt_last_dispatched,
		MIN(ts_created) AS ts_first_dispatched
	FROM customer_conversions
	GROUP BY 1
),
conversion_metrics AS (
	SELECT
		id_customer,
		id_last_answer,
		total_dispatches,
		total_answers,
		avg_minutes_response_time,
		avg_score,
		CASE WHEN total_answers > 0 THEN ROUND(100.0*(promoters - detractors)/total_answers,0)
			END AS overall_nps,
		CASE WHEN total_dispatches > 0 THEN ROUND(1.0*total_answers/total_dispatches,3)
			END AS answer_rate,
		CASE WHEN total_answers > 0 THEN ROUND(1.0*total_comments/total_answers,3)
			END AS comment_rate,
		has_pending_survey,
		dt_last_dispatched,
		ts_first_dispatched
	FROM customer_metrics
),
last_category AS (
	SELECT
		cc.id_customer,
		cc.nps_answer AS last_score,
		cc.score_category AS last_category
	FROM customer_conversions cc
	INNER JOIN customer_metrics cm
		ON cm.id_last_answer = cc.id_answer
),
second_last_answer AS (
	SELECT
		cc.id_customer,
		max(cc.id_answer) AS id_second_last_answer
	FROM customer_conversions cc
	LEFT JOIN customer_metrics cm
		ON cm.id_customer = cc.id_customer
	WHERE cc.id_answer < cm.id_last_answer
	GROUP BY 1
),
second_last_category AS (
	SELECT
		cc.id_customer,
		cc.score_category AS second_last_category
	FROM customer_conversions cc
	INNER JOIN second_last_answer sla
		ON sla.id_second_last_answer = cc.id_answer
),
last_shift AS (
	SELECT
		lc.id_customer,
		lc.last_score,
		CONCAT(slc.second_last_category,CONCAT(':',lc.last_category)) AS last_shift_type
	FROM last_category lc
	INNER JOIN second_last_category slc
		ON slc.id_customer = lc.id_customer
	WHERE lc.last_category != slc.second_last_category
),
answer_keys AS (
	SELECT
		id_answer,
		MAX(CASE WHEN tag_name = 'User Id' THEN CAST(tag_value AS BIGINT)
				END) AS id_user,
		MAX(CASE WHEN tag_name = 'CPF' THEN tag_value
				END) AS cpf
	FROM datalake_tracksale.answer_tags
	WHERE tag_name IN ('User Id','CPF')
	GROUP BY 1
),
ebdb_user AS (
	SELECT
		ak.id_answer,
		ak.id_user
	FROM answer_keys ak
	INNER JOIN datalake_ebdb_clean.user u
		ON ak.id_user = u.id
	GROUP BY 1,2
),
ebdb_cpf AS (
	SELECT
		ak.id_answer,
		ak.cpf
	FROM answer_keys ak
	INNER JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci
		ON ak.cpf = cci.cpf
	GROUP BY 1,2
),
customer_keys AS (
	SELECT
		cc.id_customer,
		MAX(COALESCE(eu.id_user,cci_e.id_user, cci_p.id_user)) AS id_user,
		MAX(COALESCE(ec.cpf,cci_e.cpf,cci_p.cpf)) AS cpf
	FROM datalake_tracksale.customer_conversions cc
	LEFT JOIN ebdb_user eu
		ON eu.id_answer = cc.id_answer
	LEFT JOIN ebdb_cpf ec
		ON ec.id_answer = cc.id_answer
	LEFT JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci_p
		ON cci_p.customer_contact = cc.customer_phone
		AND cci_p.channel = 'phone'
	LEFT JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci_e
		ON cci_e.customer_contact = cc.customer_email
		AND cci_e.channel = 'email'
	GROUP BY 1
)
SELECT
	cm.id_customer AS sk_nps_customer,
	COALESCE(ck.id_user,-1) AS sk_user,
	ck.cpf AS sk_personal_document,
	ls.last_shift_type,
	cm.total_dispatches,
	cm.total_answers,
	cm.answer_rate,
	cm.comment_rate,
	cm.avg_score,
	ls.last_score,
	cm.overall_nps,
	cm.avg_minutes_response_time,
	cm.has_pending_survey,
	cm.dt_last_dispatched,
	current_timestamp AS ts_load
FROM conversion_metrics cm
LEFT JOIN customer_keys ck
	ON ck.id_customer = cm.id_customer
LEFT JOIN last_shift ls
	ON ls.id_customer = cm.id_customer