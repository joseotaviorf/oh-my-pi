WITH events AS (
  SELECT DISTINCT LOWER(funnel_step) AS funnel_step, business_event
  FROM datalake_supply_flows.supply_events_tracking
)

SELECT
  CONCAT_WS('#',funnel_step, business_event) AS bk_funnel_step,
  funnel_step AS cd_funnel_step,
  SPLIT_PART(business_event,'_',1) AS tp_business_event,
  SPLIT_PART(business_event,'_',2) AS cd_funnel_inter_step,
  'NotMapped' AS ds_funnel_step,
  NOW() AS ts_updated
FROM events