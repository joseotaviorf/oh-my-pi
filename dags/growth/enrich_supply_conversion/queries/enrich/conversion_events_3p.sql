WITH conversion_p2q AS (
  SELECT 
    p.sk_supply_lead, 
    l3p.business_context,
    l3p.id_lead_3p AS id_lead,
    l3p.id_region,
    l3p.id_house,
    -1 AS id_lead_ebdb,
    -1 AS id_referred_by,
    'conversion_p2q' AS business_event,
    l3p.growth_status AS funnel_step,
    2 AS funnel_level,
    '3P' AS supply_source,
    '-1' AS drop_step_reason,
    COALESCE(l3p.status, -1) AS aux_product_status,
    l3p.aux_hash,
    l3p.ts_event
  FROM 
    datalake_supply_flows.prospects_3p AS p
  JOIN 
    datalake_supply_flows.landing_3p AS l3p
      ON (p.id_lead = l3p.id_lead_3p)
      AND (p.business_context = l3p.business_context)
      AND (l3p.growth_status = 'QUALIFIED')
      AND (l3p.aux_round_number = 1)
),
conversion_q2aq AS (
  SELECT 
    p.sk_supply_lead, 
    l3p.business_context,
    l3p.id_lead_3p AS id_lead,
    l3p.id_region,
    l3p.id_house,
    -1 AS id_lead_ebdb,
    -1 AS id_referred_by,
    'conversion_q2aq' AS business_event,
    l3p.growth_status AS funnel_step,
    2 AS funnel_level,
    '3P' AS supply_source,
    '-1' AS drop_step_reason,
    COALESCE(l3p.status, -1) AS aux_product_status,
    l3p.aux_hash,
    l3p.ts_event
  FROM 
    datalake_supply_flows.prospects_3p AS p
  JOIN 
    datalake_supply_flows.landing_3p AS l3p
      ON (p.id_lead = l3p.id_lead_3p)
      AND (p.business_context = l3p.business_context)
      AND (l3p.growth_status = 'AV_QUALIFIED')
      AND (l3p.aux_round_number = 1)
),
conversion_aq2o AS (
  SELECT 
    p.sk_supply_lead, 
    l3p.business_context,
    l3p.id_lead_3p AS id_lead,
    l3p.id_region,
    l3p.id_house,
    -1 AS id_lead_ebdb,
    -1 AS id_referred_by,
    'conversion_aq2o' AS business_event,
    l3p.growth_status AS funnel_step,
    2 AS funnel_level,
    '3P' AS supply_source,
    '-1' AS drop_step_reason,
    COALESCE(l3p.status, -1) AS aux_product_status,
    l3p.aux_hash,
    l3p.ts_event
  FROM 
    datalake_supply_flows.prospects_3p AS p
  JOIN 
    datalake_supply_flows.landing_3p AS l3p
    ON (p.id_lead = l3p.id_lead_3p)
    AND (p.business_context = l3p.business_context)
    AND (l3p.growth_status = 'OPPORTUNITY')
    AND (l3p.aux_round_number = 1)
),
drop_p2q AS (
  SELECT 
    l.aux_hash
  FROM 
    datalake_supply_flows.prospects_3p AS l
  LEFT ANTI JOIN 
    conversion_p2q AS c
      ON (l.id_lead = c.id_lead)
        AND (l.business_context = c.business_context)
  GROUP BY ALL
),
drop_q2aq AS (
  SELECT 
    l.aux_hash
  FROM 
    datalake_supply_flows.prospects_3p AS l
  LEFT ANTI JOIN 
    conversion_q2aq AS c
      ON (l.id_lead = c.id_lead)
        AND (l.business_context = c.business_context)
  GROUP BY ALL
),
drop_aq2o AS (
  SELECT 
    l.aux_hash
  FROM 
    datalake_supply_flows.prospects_3p AS l
  LEFT ANTI JOIN 
    conversion_aq2o AS c
      ON (l.id_lead = c.id_lead)
        AND (l.business_context = c.business_context)
  GROUP BY ALL
),
discards_events_p2q AS (
  SELECT 
    *
  FROM 
    datalake_supply_flows.landing_3p AS l3p
  JOIN drop_p2q
    USING (aux_hash)
  WHERE 
    aux_round_number = 1
    AND growth_status = 'PROSPECT'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l3p.id_lead_3p ORDER BY l3p.ts_event) = 1 
),
discards_events_q2aq AS (
  SELECT 
    *
  FROM 
    datalake_supply_flows.landing_3p AS l3p
  JOIN drop_q2aq 
    USING (aux_hash)
  WHERE 
    aux_round_number = 1
    AND growth_status = 'QUALIFIED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l3p.id_lead_3p ORDER BY l3p.ts_event) = 1 
),
discards_events_aq2o AS (
  SELECT 
    *
  FROM 
    datalake_supply_flows.landing_3p AS l3p
  JOIN drop_aq2o
    USING (aux_hash)
  WHERE 
    aux_round_number = 1
    AND growth_status = 'AV_QUALIFIED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l3p.id_lead_3p ORDER BY l3p.ts_event) = 1 
),
step_p2q AS (
  SELECT 
    ls.sk_supply_lead, 
    l3p.business_context,
    ls.id_lead,
    l3p.id_region,
    l3p.id_house,
    -1 AS id_lead_ebdb,
    -1 AS id_referred_by,
    'drop_p2q' AS business_event,
    l3p.growth_status AS funnel_step,
    2 AS funnel_level,
    '3P' AS supply_source,
    COALESCE(l3p.reason, -2) AS drop_step_reason,
    COALESCE(l3p.status, -1) AS aux_product_status,
    l3p.aux_hash,
    l3p.ts_event
  FROM 
    datalake_supply_flows.leads_sks AS ls
  JOIN 
    discards_events_p2q AS l3p
      ON ls.id_lead = l3p.id_lead_3p
        AND (ls.source = '3P')
  UNION ALL
  SELECT 
    *
  FROM 
    conversion_p2q
),
step_q2aq AS (
  SELECT 
    ls.sk_supply_lead, 
    l3p.business_context,
    ls.id_lead,
    l3p.id_region,
    l3p.id_house,
    -1 AS id_lead_ebdb,
    -1 AS id_referred_by,
    'drop_q2aq' AS business_event,
    l3p.growth_status AS funnel_step,
    2 AS funnel_level,
    '3P' AS supply_source,
    COALESCE(l3p.reason, -2) AS drop_step_reason,
    COALESCE(l3p.status, -1) AS aux_product_status,
    l3p.aux_hash,
    l3p.ts_event
  FROM 
    datalake_supply_flows.leads_sks AS ls
  JOIN 
    discards_events_q2aq AS l3p
      ON ls.id_lead = l3p.id_lead_3p
      AND (ls.source = '3P')
  UNION ALL
  SELECT 
    *
  FROM 
    conversion_q2aq
),
step_aq2o AS (
  SELECT 
    ls.sk_supply_lead, 
    l3p.business_context,
    ls.id_lead,
    l3p.id_region,
    l3p.id_house,
    -1 AS id_lead_ebdb,
    -1 AS id_referred_by,
    'drop_aq2o' AS business_event,
    l3p.growth_status AS funnel_step,
    2 AS funnel_level,
    '3P' AS supply_source,
    COALESCE(l3p.reason, -2) AS drop_step_reason,
    COALESCE(l3p.status, -1) AS aux_product_status,
    l3p.aux_hash,
    l3p.ts_event
  FROM 
    datalake_supply_flows.leads_sks AS ls
  JOIN 
    discards_events_aq2o AS l3p
      ON ls.id_lead = l3p.id_lead_3p
      AND (ls.source = '3P')
  UNION ALL
  SELECT 
    *
  FROM 
    conversion_aq2o
),
all_tb AS (
  SELECT *
  FROM step_p2q
  UNION ALL
  SELECT *
  FROM step_q2aq
  UNION ALL
  SELECT *
  FROM step_aq2o
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
    NOW() AS ts_load
FROM all_tb