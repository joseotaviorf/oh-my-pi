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
  acq_lead.sk_supply_lead,
  acq_lead.cd_supply_source,
  acq_lead.nm_business_context,
  acq_lead.id_lead,
  acq_lead.id_lead_ebdb,
  acq_lead.id_original_lead,
  acq_lead.id_prospect,
  acq_lead.id_house,
  acq_lead.tp_track_campaign,
  acq_lead.tp_track_medium,
  acq_lead.tp_track_source,
  acq_lead.nm_medium,
  acq_lead.nm_source,
  acq_lead.nm_campaign,
  acq_lead.tp_lead,
  acq_lead.ts_updated,
  CONCAT_WS(
    '#',
    acq_lead.sk_supply_lead,
    acq_lead.cd_supply_source,
    acq_lead.nm_business_context
  ) AS bk_acq_lead
FROM
  acq_lead