SELECT 
    nps.id AS sk_nps_answer,
    nps.score_category,
    c.customer_type,
    nps.nps_answer AS score,
    c.metric_group AS nps_campaign,
    nps.ts_answer_sent_local AS ts_answered,
    NOW() AS ts_load
FROM
    (SELECT * FROM datalake_tracksale.answer
	UNION ALL
	SELECT * FROM datalake_casa_mineira_tracksale.answer) AS nps
JOIN
    (SELECT * FROM datalake_tracksale.customer_conversions
    UNION ALL
    SELECT * FROM datalake_casa_mineira_tracksale.customer_conversions) AS cc
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