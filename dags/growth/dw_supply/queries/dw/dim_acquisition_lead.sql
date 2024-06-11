WITH acq_lead AS (
  SELECT 
    sk_supply_lead,
    supply_source AS cd_supply_source,
    business_context AS nm_business_context,
    id_lead,
    id_lead_ebdb,
    original_lead AS id_original_lead,
    id_prospect,
    id_house,
    aux_database_tracking_campaign AS tp_track_campaign,
    aux_database_tracking_medium AS tp_track_medium,
    aux_database_tracking_source AS tp_track_source,
    medium AS nm_medium, 
    source AS nm_source, 
    campaign AS nm_campaign,
    lead_type AS tp_lead,
    NOW() AS ts_updated
  FROM datalake_supply_flows.supply_events_tracking
  WHERE funnel_step = 'PROSPECT'
    AND sk_supply_lead IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY sk_supply_lead, supply_source, business_context ORDER BY ts_event_adjusted DESC) = 1
)

SELECT 
  *,
  CONCAT_WS(
    '#',
    sk_supply_lead, 
    cd_supply_source, 
    nm_business_context
  ) AS bk_acq_lead
FROM acq_lead