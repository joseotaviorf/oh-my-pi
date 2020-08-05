SELECT
	a.id AS sk_nps_answer,
	ad.campaign_step,
	a.score_category,
	a.nps_comment AS comment,
	a.ts_answer_sent AS ts_answered
FROM datalake_tracksale.answer a
INNER JOIN datalake_tracksale.nps_customer_conversions ncc
	ON ncc.id_answer = a.id
LEFT JOIN datalake_tracksale_answer_drivers.answer_drivers ad
	ON ad.id_answer = a.id
