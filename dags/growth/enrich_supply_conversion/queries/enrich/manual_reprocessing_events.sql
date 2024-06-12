 WITH all_entities AS (
  SELECT 
    'house' AS entity_type, 
    id_entity, 
    business_context
  FROM 
    datalake_supply_flows.conversion_staging
  WHERE 
    source != 'WOLOLO'
  GROUP BY 1, 2, 3
  UNION ALL
  SELECT 
    'lead' AS entity_type, 
    id_lead, 
    business_context
  FROM 
    datalake_supply_flows.conversion_events
  WHERE 
    id_lead IS NOT NULL
  GROUP BY 1, 2, 3
),
join_mailing AS (
  SELECT
      id_lead,
      type,
      business_context,
      id_campaign,
      table_name,
      description,
      ops_partner, 
      ops_agent, 
      ops_objective, 
      ops_approach, 
      ops_contact_medium, 
      application,
      2 AS weight,
      ts_created
    FROM 
      datalake_olos_dialer.reprocessing_mailing
    UNION ALL
    SELECT
      id_lead_ebdb AS id_lead,
      reprocessed AS type,
      business_context,
      CAST(NULL AS BIGINT)  AS id_campaign,
      'rene_descartes' AS table_name,
      CAST(NULL AS STRING)  AS description,
      CAST(NULL AS STRING) AS ops_partner, 
      CAST(NULL AS STRING) AS ops_agent, 
      CAST(NULL AS STRING) AS ops_objective, 
      CAST(NULL AS STRING) AS ops_approach, 
      CAST(NULL AS STRING) AS ops_contact_medium, 
      application,
      1 AS weight,
      ts_event AS ts_created
    FROM
      datalake_supply_flows.acquisition_tracking
    WHERE
      reprocessed = 'automatically_reprocessed'
      AND funnel_step = 'LEAD'
),
mailing AS (
  SELECT 
    id_lead,
    business_context,
    type,
    id_campaign,
    table_name,
    description,
    ops_partner, 
    ops_agent, 
    ops_objective,
    ops_approach, 
    ops_contact_medium, 
    application,
    ts_created
  FROM 
    join_mailing
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_lead, business_context ORDER BY weight ASC, ts_created DESC) = 1 -- Getting the last reprocessing event from

),
events AS (
  SELECT 
    id_lead,
    business_context,
    id_user_registrant,
    ts_event
  FROM 
    datalake_olos_dialer.reprocessing_events
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_lead, business_context ORDER BY ts_event DESC) = 1 -- Getting the last event for each lead and business context
)

SELECT
    ae.id_entity,
    ae.business_context,
    re.id_user_registrant,
    ae.entity_type AS reprocessing_entity_type,
    rm.type AS reprocessing_type,
    rm.id_campaign,
    rm.table_name,
    rm.description,
    rm.ops_partner, 
    rm.ops_agent, 
    rm.ops_objective,
    rm.ops_approach, 
    rm.ops_contact_medium, 
    rm.application,
    re.ts_event AS ts_conversion_event,
    rm.ts_created,
    NOW() AS ts_load
FROM
  all_entities AS ae
JOIN mailing AS rm 
  ON (ae.id_entity = rm.id_lead)
    AND (ae.business_context = rm.business_context)
JOIN events AS re
  ON (rm.id_lead = re.id_lead)
    AND (rm.business_context = re.business_context)