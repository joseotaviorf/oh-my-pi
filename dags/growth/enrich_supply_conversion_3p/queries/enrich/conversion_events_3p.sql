WITH all_tb AS (
  SELECT *
  FROM datalake_supply_flows_migrate.qualified_3p
  UNION ALL
  SELECT *
  FROM datalake_supply_flows_migrate.av_qualified_3p
  UNION ALL
  SELECT *
  FROM datalake_supply_flows_migrate.opportunity_3p
)

SELECT 

    sk_supply_lead,
    id_lead,
    id_region,
    id_house,
    id_lead_ebdb,
    id_referred_by,
    supply_source,
    business_context,
    business_event,
    funnel_step,
    funnel_level,
    drop_step_reason,
    aux_product_status,
    aux_hash,
    CASE 
        WHEN funnel_step = 'QUALIFIED' THEN 3
        WHEN funnel_step = 'AV_QUALIFIED' THEN 3
        WHEN funnel_step = 'OPPORTUNITY' THEN 2
        WHEN funnel_step = 'FIRST_LISTING' THEN 1
    END AS weight,
    ts_event,
    NOW() AS ts_load,
    YEAR(ts_event) AS year,
    MONTH(ts_event) AS month,
    DAY(ts_event) AS day
FROM all_tb