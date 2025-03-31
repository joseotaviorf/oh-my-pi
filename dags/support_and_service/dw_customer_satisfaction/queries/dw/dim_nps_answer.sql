SELECT
	a.id AS sk_nps_answer,
	at.tag_value AS campaign_step,
	a.id_campaign,
	a.score_category,
	a.nps_answer,
	a.nps_comment AS comment,
	cc.is_customer_identified,
	current_timestamp AS ts_load,
	a.ts_answer_sent_local AS ts_answered
FROM 
	datalake_tracksale.answer AS a 
INNER JOIN datalake_tracksale.customer_conversions AS cc
	ON cc.id_answer = a.id
LEFT JOIN datalake_tracksale.answer_tags AS at
	ON at.id_answer = a.id
	AND at.tag_name = 'Etapa'