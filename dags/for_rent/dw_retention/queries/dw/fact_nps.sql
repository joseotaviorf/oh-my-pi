SELECT
    MD5(CONCAT(ct.id_termination, cc.id_customer)) AS sk_nps,
    ct.id_termination AS sk_termination,
    MD5(cc.id_customer) AS sk_nps_respondent,
    nps.id AS sk_nps_answer,
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
    datalake_nps_answer_drivers.answer_drivers AS ad
        ON ad.id_answer = nps.id
JOIN
    datalake_offboarding.contract_termination AS ct
        ON ct.id_contract = ad.id_contract
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
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY ct.id_termination, cc.id_customer ORDER BY nps.ts_answer_sent_utc DESC) = 1