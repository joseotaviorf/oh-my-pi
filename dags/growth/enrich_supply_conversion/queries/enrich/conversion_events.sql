WITH events_3p AS (
    SELECT
      c3p.id_lead,
      COALESCE(c3p.id_house, -1) AS id_entity,
      NULL AS id_user_registrant,
      c3p.business_context,
      c3p.supply_source,
      c3p.funnel_step AS step,
      c3p.weight,
      c3p.ts_event,
      c3p.ts_event AS ts_event_adjusted,
      IF(c3p.business_event LIKE 'drop%', c3p.ts_event, NULL) AS ts_first_discard,
      IF(c3p.business_event LIKE 'drop%', c3p.ts_event, NULL) AS ts_last_discard,
      NULL AS rev,
      c3p.business_event,
      c3p.drop_step_reason,
      'T7.0' AS aux_group,
      FALSE AS aux_data_event
    FROM 
      datalake_supply_flows.conversion_events_3p AS c3p
    LEFT ANTI JOIN 
      datalake_supply_flows.conversion_attributed_events AS t2
        ON (c3p.id_house = t2.id_entity)
        AND (c3p.business_context = t2.business_context)
        AND (t2.aux_group LIKE 'T2%')
),
original_events AS (
    SELECT 
      * EXCEPT (year, month, day)
    FROM 
      datalake_supply_flows.conversion_attributed_events
    UNION ALL
    SELECT 
      *
    FROM 
      events_3p
),
base AS (
  SELECT
    id_lead,
    id_entity,
    business_context,
    supply_source,
    step,
    ts_event_adjusted
  FROM 
    original_events
),
pivot_table AS (
  SELECT 
    *
  FROM 
    base
    PIVOT (
      MIN(ts_event_adjusted)
      FOR (step) IN (
          'QUALIFIED' AS ts_qualified,
          'AV_QUALIFIED' AS ts_available_qualified,
          'OPPORTUNITY' AS ts_opportunity,
          'FIRST_LISTING' AS ts_first_listing
      )
    )
),
fill_date (
  SELECT 
    id_lead,
    id_entity,
    business_context,
    supply_source,
    ts_qualified AS ts_qualified_original, 
    COALESCE(ts_qualified, ts_available_qualified, ts_opportunity, ts_first_listing) AS ts_qualified,
    ts_available_qualified AS ts_available_qualified_original, 
    COALESCE(ts_available_qualified, ts_opportunity, ts_first_listing) AS ts_available_qualified,
    ts_opportunity AS ts_opportunity_original, 
    COALESCE(ts_opportunity, ts_first_listing) AS ts_opportunity,
    ts_first_listing
  FROM pivot_table
),
events_to_insert AS (
  SELECT 
    id_lead,
    id_entity,
    business_context,
    supply_source,
    step,
    ts_event
  FROM 
    fill_date
    UNPIVOT (
        ts_event FOR step IN (
          ts_qualified AS QUALIFIED,
          ts_available_qualified AS AV_QUALIFIED,
          ts_opportunity AS OPPORTUNITY,
          ts_first_listing AS FIRST_LISTING
        )
  )
  EXCEPT ALL
  SELECT 
    *
  FROM 
    base
),
last_extract AS (
  SELECT 
    id_lead,
    id_entity,
    NULL AS id_user_registrant,
    business_context,
    supply_source,
    step,
    CASE 
      WHEN step = 'QUALIFIED' THEN 3
      WHEN step = 'AV_QUALIFIED' THEN 3
      WHEN step = 'OPPORTUNITY' THEN 2
      WHEN step = 'FIRST_LISTING' THEN 1
    END AS weight,
    NULL AS ts_event_original,
    ts_event AS ts_event_adjusted,
    NULL AS ts_first_discard,
    NULL AS ts_last_discard,
    NULL AS rev,
    CASE 
      WHEN step = 'QUALIFIED' THEN 'conversion_p2q'
      WHEN step = 'AV_QUALIFIED' THEN 'conversion_q2aq'
      WHEN step = 'OPPORTUNITY' THEN 'conversion_aq2o'
      WHEN step = 'FIRST_LISTING' THEN 'conversion_o2fl'
    END AS business_event,
    NULL AS reason,
    'T6.0' AS aux_group,
    TRUE AS aux_data_event
  FROM 
    events_to_insert
),
fill_events (
  SELECT 
    * 
  FROM 
    last_extract AS le
  LEFT ANTI JOIN 
    datalake_supply_flows.conversion_events_3p AS ce3
      ON (le.id_entity = ce3.id_house)
        AND (le.business_context = ce3.business_context)
        AND (le.step = ce3.funnel_step)
)

SELECT 
  *
FROM 
  original_events
UNION ALL 
SELECT 
  *
FROM 
  fill_events