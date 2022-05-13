WITH dispatch_attributes AS (
    SELECT 
        id, 
        email, 
        phone, 
        dispatch_time 
    FROM 
        datalake_tracksale.dispatch_attributes
    UNION ALL
    SELECT 
        id, 
        email, 
        phone, 
        dispatch_time 
    FROM 
        datalake_casa_mineira_tracksale.dispatch_attributes
)
SELECT DISTINCT
    ct.id_contract,
    ct.id_nps_answer,
    CASE
        WHEN ct.score_category = 'promoter' THEN 1
        WHEN ct.score_category = 'detractor' THEN -1
        WHEN ct.score_category = 'passive' THEN 0
        ELSE NULL
    END AS score,
    ct.customer_type,
    ct.nps_comment AS comment,
    DATEDIFF(ct.ts_nps_answer_sent, ct.dt_termination) AS ldt_dt_termination_to_answer,
    DATEDIFF(ct.ts_nps_answer_sent, ct.ts_termination_finished) AS ldt_termination_finished_to_answer,
    DATE(da.dispatch_time) AS dt_sent, 
    ct.dt_termination,
    DATE(ct.ts_termination_finished) AS dt_termination_finished,
    ct.ts_nps_answer_sent AS ts_answer_sent
FROM 
    datalake_offboarding.contract_termination ct
LEFT JOIN 
    dispatch_attributes da
        ON ct.id_dispatch_lot = da.id
        AND (ct.customer_email = da.email OR ct.customer_phone = da.phone)
WHERE 
    UPPER(ct.campaign_name) LIKE '%OFFBOARDING%' 
    AND ct.status <> 'CANCELED'
    AND ct.is_answered = TRUE
    AND DATE(da.dispatch_time) > DATE('2020-11-01')