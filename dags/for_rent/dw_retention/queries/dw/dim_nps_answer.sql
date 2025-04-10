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
    nps.id AS sk_nps_answer,
    nps.score_category,
    nps.nps_answer AS score,
    c.customer_type,
    nps.nps_comment,
    c.metric_group AS nps_campaign,
    nps.ts_answer_sent_local AS ts_answered,
    NOW() AS ts_load
FROM
    (SELECT * FROM datalake_tracksale.answer
	UNION ALL
	SELECT * FROM datalake_casa_mineira_tracksale.answer) AS nps
JOIN
    union_customer_conversions AS cc
        ON cc.id_answer = nps.id
JOIN 
    (SELECT * FROM datalake_tracksale.dispatch
    UNION ALL
    SELECT * FROM datalake_casa_mineira_tracksale.dispatch) AS d
        ON cc.id_dispatch_lot = d.id
JOIN 
    (SELECT * FROM datalake_tracksale.campaign
    UNION ALL
    SELECT * FROM datalake_casa_mineira_tracksale.campaign) AS c
        ON c.id = d.id_campaign
WHERE 
    nps.id > 0
    AND c.metric_group IN ('iqoffboarding','ppoffboarding')
    AND c.business_context = 'forRent'