SELECT
	a.id AS sk_nps_answer,
	at.tag_value AS campaign_step,
	a.score_category,
	a.nps_comment AS comment,
	a.ts_answer_sent AS ts_answered,
	current_timestamp AS ts_load
FROM datalake_tracksale.answer a
INNER JOIN datalake_tracksale.customer_conversions cc
	ON cc.id_answer = a.id
LEFT JOIN datalake_tracksale.answer_tags at
	ON at.id_answer = a.id
	AND at.tag_name = 'Etapa'
