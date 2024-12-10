SELECT DISTINCT
    id_funnel_step AS sk_funnel_step,
    funnel_step,
    SPLIT_PART(business_event,'_',1) AS business_event,
    SPLIT_PART(business_event,'_',2) AS funnel_inter_step,
    NOW() AS ts_load
FROM 
    datalake_ciq.ciq_supply_events_tracking
WHERE
    id_funnel_step <> -1
