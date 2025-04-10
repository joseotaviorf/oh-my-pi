WITH union_customer_conversions AS (
  SELECT
    id_dispatch,
    id_dispatch_user,
    id_dispatch_lot,
    id_campaign,
    id_user,
    id_customer,
    id_answer,
    uuid_person,
    customer_email,
    customer_phone,
    is_customer_identified,
    customer_type,
    status,
    ts_dispatch_created
  FROM
    datalake_tracksale.customer_conversions
  UNION ALL
  SELECT
    id_dispatch,
    NULL AS id_dispatch_user,
    id_dispatch_lot,
    NULL AS id_campaign,
    NULL AS id_user,
    id_customer,
    id_answer,
    NULL AS uuid_person,
    customer_email,
    customer_phone,
    is_customer_identified,
    NULL AS customer_type,
    NULL AS status,
    NULL AS ts_dispatch_created
  FROM
    datalake_casa_mineira_tracksale.customer_conversions
)
SELECT
	a.id AS sk_nps_answer,
	at.tag_value AS campaign_step,
	a.score_category,
	a.nps_comment AS comment,
	a.ts_answer_sent_local AS ts_answered,
	cc.is_customer_identified,
	current_timestamp AS ts_load
FROM 
	(SELECT * FROM datalake_tracksale.answer
	UNION ALL
	SELECT * FROM datalake_casa_mineira_tracksale.answer) a -- we are merging historical data from Casa Mineira's Tracksale account
INNER JOIN 
	union_customer_conversions cc
	ON cc.id_answer = a.id
LEFT JOIN 
	(SELECT * FROM datalake_tracksale.answer_tags
	UNION ALL
	SELECT * FROM datalake_casa_mineira_tracksale.answer_tags) at
	ON at.id_answer = a.id
	AND at.tag_name = 'Etapa'