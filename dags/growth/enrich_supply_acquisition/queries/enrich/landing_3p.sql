WITH tb_aux AS (
  -- In this CTE i join the lead_3p_status_changes with the lead_3p table to get the id_region
  SELECT
    lsc.id_lead_3p,
    lsc.business_context,
    lsc.growth_status,
    lsc.status,
    l.city,
    l.id_region,
    l.uuid_lead,
    lsc.ts_status_started AS ts_event
  FROM
    datalake_rede_supply.lead_3p_status_changes AS lsc
  LEFT JOIN datalake_brokers_supply_processor.lead_3p AS l
      ON (lsc.id_lead_3p = l.id)
),
discards AS (
  -- Getting the discards reasons
  SELECT
    id_lead_3p,
    business_context,
    reason,
    reason_type,
    status_when_reason_started AS status,
    growth_status_when_reason_started AS growth_status
  FROM
    datalake_rede_supply.lead_3p_reason_changes
),
pivot_table AS (
  -- Pivot the timestamps to get the first timestamp of each status
  SELECT
    id_lead_3p,
    business_context,
    status,
    uuid_lead,
    city,
    id_region,
    LEAST(ts_lead, ts_prospect, ts_qualified, ts_opportunity, ts_first_listing) AS ts_lead,
    LEAST(ts_prospect, ts_qualified, ts_opportunity, ts_first_listing) AS ts_prospect,
    LEAST(ts_qualified, ts_opportunity, ts_first_listing) AS ts_qualified,
    LEAST(ts_qualified, ts_opportunity, ts_first_listing) AS ts_av_qualified,
    LEAST(ts_opportunity, ts_first_listing) AS ts_opportunity,
    ts_first_listing
  FROM tb_aux
  PIVOT (
    MIN(ts_event)
    FOR (growth_status) IN (
      'LEAD' AS ts_lead,
      'PROSPECT' AS ts_prospect,
      'QUALIFIED' AS ts_qualified,
      'OPPORTUNITY' AS ts_opportunity,
      'FIRST_LISTING' AS ts_first_listing
    )
  )
),
denorm_table AS (
  SELECT 
    id_lead_3p,
    business_context,
    status,
    uuid_lead,
    city,
    id_region,
    -- Hard rule to change names
    CASE 
      WHEN growth_status = 'ts_lead' THEN 'LEAD'
      WHEN growth_status = 'ts_prospect' THEN 'PROSPECT'
      WHEN growth_status = 'ts_qualified' THEN 'QUALIFIED'
      WHEN growth_status = 'ts_av_qualified' THEN 'AV_QUALIFIED'
      WHEN growth_status = 'ts_opportunity' THEN 'OPPORTUNITY'
      WHEN growth_status = 'ts_first_listing' THEN 'FIRST_LISTING'
    END as growth_status, 
    ts_event
  FROM pivot_table
  UNPIVOT (ts_event FOR growth_status IN (ts_lead, ts_prospect, ts_qualified, ts_av_qualified, ts_opportunity, ts_first_listing))
)

-- Joining all the discards reason using these 4 keys
SELECT 
  denorm_table.id_lead_3p,
  h.id AS id_house,
  denorm_table.id_region,
  denorm_table.business_context,
  denorm_table.growth_status,
  denorm_table.status,
  denorm_table.city,
  discards.reason,
  discards.reason_type,
  ROW_NUMBER() OVER (PARTITION BY id_lead_3p, business_context, growth_status ORDER BY ts_event) AS aux_round_number,
  MD5(CONCAT_WS('_', id_lead_3p, business_context)) AS aux_hash,
  denorm_table.ts_event
FROM denorm_table
LEFT JOIN discards
  USING (id_lead_3p, business_context, growth_status, status)
LEFT JOIN datalake_ebdb_clean.house AS h
  ON h.id_external = denorm_table.uuid_lead