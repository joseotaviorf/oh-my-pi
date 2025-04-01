WITH bp_status AS (
  SELECT
    bps.id_demand_prospect_conversion_event,
    bps.id_buyer_prospect,
    ce.id_offer,
    ce.id_house,
    ce.id_booking,
    ce.id_region,
    bps.prospect_event_name,
    bps.status_trigger_event_name,
    CASE
      WHEN bps.prospect_event_name = 'USER RECOVERY' THEN 'RBP'
      WHEN
        bps.prospect_event_name IN ('USER FIRST ACTIVATION', 'USER FIRST ACTIVATION IN CITY GROUP')
      THEN
        'NBP'
    END AS bp_type,
    bps.city_group,
    bps.status_detail,
    bps.status,
    bps.ts_status_started AS ts_activation,
    COALESCE(
      bps.ts_status_ended,
      LEAD(bps.ts_status_started) OVER (
          PARTITION BY bps.id_buyer_prospect
          ORDER BY bps.ts_status_started
        )
    ) AS ts_activation_end
  FROM
    datalake_demand_flows.buyer_prospect_status AS bps
  LEFT JOIN 
    datalake_demand_flows.conversion_events AS ce
      ON bps.id_demand_prospect_conversion_event = ce.id_demand_prospect_conversion_event
  QUALIFY
    bps.ts_status_started = MIN(bps.ts_status_started) OVER (
        PARTITION BY bps.id_buyer_prospect, bps.ts_status_ended
        ORDER BY bps.ts_status_started
      )
)
SELECT
  MD5(
    CONCAT(
      id_buyer_prospect,
      COALESCE(id_offer, -1),
      COALESCE(id_booking, -1),
      bp_status.ts_activation
    )
  ) AS id_buyer_prospect_type,
  bp_status.id_buyer_prospect AS id_prospect,
  bp_status.id_offer,
  bp_status.id_house,
  bp_status.id_booking,
  bp_status.id_region,
  bp_status.id_demand_prospect_conversion_event,
  bp_status.prospect_event_name,
  bp_status.status_trigger_event_name,
  bp_status.bp_type,
  bp_status.city_group,
  slpc.price_segment,
  slpc.change_number AS price_change_number,
  bp_status.ts_activation,
  bp_status.ts_activation_end,
  NOW() AS ts_load
FROM
  bp_status
LEFT JOIN 
  datalake_sale_listings.sale_listing_price_changes AS slpc
    ON bp_status.id_house = slpc.id_house
    AND bp_status.ts_activation BETWEEN
      slpc.ts_price_started
    AND
      COALESCE(slpc.ts_price_ended, NOW())
WHERE
  bp_status.prospect_event_name IN (
    'USER FIRST ACTIVATION', 'USER FIRST ACTIVATION IN CITY GROUP', 'USER RECOVERY'
  )
  AND bp_status.status = 'ACTIVE'
QUALIFY 
  slpc.change_number = MAX(slpc.change_number) OVER (PARTITION BY bp_status.id_buyer_prospect, bp_status.ts_activation, bp_status.id_house)