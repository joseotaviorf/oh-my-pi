WITH taxonomy AS (
    SELECT 
      ct.id_lead,
      ct.id_house,
      ct.business_context,
      ct.id_user_registrant,
      ct.source,
      COALESCE(mr_leads.application, mr_houses.application, ct.application, ops.application) AS application,
      ct.funnel_step,
      ct.id_region,
      -- We are considering the application of the reprocessing and in null cases, we get it from the conversion directly
      COALESCE(mr_leads.ops_objective, mr_houses.ops_objective, ct.ops_objective, ops.ops_objective) AS ops_objective,
      COALESCE(mr_leads.ops_agent, mr_houses.ops_agent, ct.ops_agent, ops.ops_agent) AS ops_agent,
      COALESCE(mr_leads.ops_partner, mr_houses.ops_partner, ct.ops_partner, ops.ops_partner) AS ops_partner,
      -- These fields are not present in the manual reprocessing table
      ct.ops_approach,
      ct.ops_contact_medium,
      ct.ts_event,
      COALESCE(mr_leads.reprocessing_type, mr_houses.reprocessing_type) AS reprocessed,
      COALESCE(mr_leads.reprocessing_entity_type, mr_houses.reprocessing_entity_type) AS reprocessing_entity_type,
      COALESCE(mr_leads.table_name, mr_houses.table_name) AS reprocessing_table_name,
      COALESCE(mr_leads.ts_created, mr_houses.ts_created) AS ts_reprocessing_event,
      COALESCE(mr_leads.id_user_registrant, mr_houses.id_user_registrant) AS reprocessing_id_user_registrant
    FROM 
      datalake_supply_flows.conversion_taxonomy AS ct
    LEFT JOIN 
      datalake_supply_flows.operations_agents AS ops
        ON (ops.id_user = ct.id_user_registrant)
    LEFT JOIN 
      datalake_supply_flows.manual_reprocessing_events AS mr_leads 
        ON (ct.id_lead = mr_leads.id_entity)
        AND (ct.business_context = mr_leads.business_context)
        AND (mr_leads.reprocessing_entity_type = 'lead')
    LEFT JOIN 
      datalake_supply_flows.manual_reprocessing_events AS mr_houses
        ON (ct.id_house = mr_houses.id_entity)
        AND (ct.business_context = mr_houses.business_context)
        AND mr_houses.reprocessing_entity_type = 'house'  
),
conversions AS (
  SELECT 
    ce.id_lead,
    ce.id_entity,
    ce.id_user_registrant,
    ct.id_user_registrant AS id_user_conversion,
    ct.id_region,
    ce.business_context,
    ce.supply_source,
    ce.step,
    ce.weight,
    ce.rev,
    ce.business_event,
    ce.reason,
    ce.aux_group,
    ce.aux_data_event,
    ct.application,
    ce.step,
    ct.ops_objective,
    ct.ops_agent,
    ct.ops_partner,
    ct.ops_approach,
    ct.ops_contact_medium,
    ct.reprocessed,
    ct.reprocessing_entity_type,
    ct.reprocessing_table_name,
    ct.reprocessing_id_user_registrant,
    ce.ts_event_original,
    ce.ts_event_adjusted,
    ce.ts_first_discard,
    ce.ts_last_discard,
    ct.ts_reprocessing_event
  FROM
    datalake_supply_flows.conversion_events AS ce
  LEFT JOIN taxonomy AS ct
    ON (ce.id_entity = ct.id_house)
      AND (ce.business_context = ct.business_context)
      AND (ct.source != 2)
  WHERE weight <= 3
),
discards AS (
 SELECT 
    ce.id_lead,
    ce.id_entity,
    ce.id_user_registrant,
    ct.id_user_registrant AS id_user_conversion,
    ct.id_region,
    ce.business_context,
    ce.supply_source,
    ce.step,
    ce.weight,
    ce.rev,
    ce.business_event,
    ce.reason,
    ce.aux_group,
    ce.aux_data_event,
    ct.application,
    ce.step,
    ct.ops_objective,
    ct.ops_agent,
    ct.ops_partner,
    ct.ops_approach,
    ct.ops_contact_medium,
    ct.reprocessed,
    ct.reprocessing_entity_type,
    ct.reprocessing_table_name,
    ct.reprocessing_id_user_registrant,
    ce.ts_event_original,
    ce.ts_event_adjusted,
    ce.ts_first_discard,
    ce.ts_last_discard,
    ct.ts_reprocessing_event
  FROM
    datalake_supply_flows.conversion_events AS ce
  LEFT JOIN taxonomy AS ct
    ON (ce.id_lead = ct.id_lead)
      AND (ce.business_context = ct.business_context)
      AND (ct.source = 2)
  WHERE ce.weight > 3
),
joined_events AS (
  SELECT 
    *
  FROM conversions
  UNION ALL
  SELECT 
    *
  FROM discards
),
applied_rules AS (
  SELECT 
    cf.id_lead,
    cf.id_entity,
    cf.id_user_registrant,
    cf.id_user_conversion,
    cf.business_context,
    cf.supply_source,
    cf.step,
    cf.weight,
    cf.ts_event_original,
    cf.ts_event_adjusted,
    cf.ts_first_discard,
    cf.ts_last_discard,
    cf.rev,
    cf.business_event,
    cf.reason,
    cf.aux_group,
    cf.aux_data_event,
    cf.reprocessed,
    cf.reprocessing_entity_type,
    cf.reprocessing_table_name,
    cf.ts_reprocessing_event,
    cf.reprocessing_id_user_registrant,
    COALESCE(cf.id_region, h.id_region) AS id_region,
    /*
    Rule: If we have an origin, we continue with it.
    In case of null, we check the id of the user who performed that operation, 
    if we have it we continue with the filling of IS analyst information, if not
    then we check the ID_USER_REGISTRANT and if we have it, we consider FSS flow
    */
    CASE
      WHEN (cf.ops_agent IS NOT NULL) AND (weight < 3)
        THEN cf.application
      WHEN cf.supply_source = '3P'
        THEN 'supplyprocessor'
      WHEN cf.application IS NOT NULL
        THEN cf.application
      WHEN cf.id_user_registrant IS NOT NULL
        THEN 'full_self_service'
      ELSE 'not_mapped'
    END AS application_staging,
    cf.ops_agent,
    cf.ops_approach,
    cf.ops_contact_medium,
    cf.ops_objective,
    cf.ops_partner
  FROM 
    joined_events AS cf
  LEFT JOIN 
    datalake_ebdb_clean.house AS h
      ON (cf.id_entity = h.id)
),
conversion_final AS (
  SELECT 
    *,   
    /*
      Cases created by data lose the tracking of application
      I changed the previous CTE with the name APPLICATION_STAGING
      If it is an event created by data, I look for the most "important" event -> FIRST LISTING -> OPPORTUNITY
    */
    CASE 
      WHEN aux_group = 'T6.0'
        THEN 
          FIRST_VALUE(application_staging) OVER (
            PARTITION BY id_entity, business_context
            ORDER BY aux_group ASC, ts_event_adjusted ASC
          ) 
        ELSE application_staging
    END AS application
  FROM 
    applied_rules
),
house_supply_source AS (
  SELECT 
    id_house, 
    business_context, 
    CASE 
      WHEN ownership = 'THIRD_PARTY' THEN '3P'
      WHEN ownership = 'STANDARD' THEN '1P'
    END AS supply_source
  FROM 
    datalake_ebdb_listing.listing_business_context
),
aux_tab AS (
  SELECT
    h.id_lead AS id_lead_ebdb, 
    id_entity,
    IF(weight <= 3, id_entity, cl.id_house) AS id_house,
    IF(weight <= 3, NULL, id_entity) AS id_prospect,
    id_region,
    id_user_registrant,
    id_user_conversion,
    h.business_context,
    COALESCE(h.supply_source, hsc.supply_source) AS supply_source,
    step AS funnel_step,
    business_event,
    application,
    reason,
    ops_agent,
    ops_approach,
    ops_contact_medium,
    ops_objective,
    ops_partner,
    reprocessed,
    reprocessing_entity_type,
    reprocessing_table_name,
    aux_group,
    aux_data_event,
    CAST(ts_event_original AS TIMESTAMP) AS ts_event_original,
    CAST(ts_event_adjusted AS TIMESTAMP) AS ts_event_adjusted,
    CAST(ts_first_discard AS TIMESTAMP) AS ts_first_discard,
    CAST(ts_last_discard AS TIMESTAMP) AS ts_last_discard,
    CAST(ts_reprocessing_event AS TIMESTAMP) AS ts_reprocessing_event,
    NOW() AS ts_load
  FROM 
    conversion_final AS h
  LEFT JOIN 
    house_supply_source AS hsc
      ON (h.id_entity = hsc.id_house)
      AND (h.business_context = hsc.business_context)
  LEFT JOIN 
    datalake_supply_flows.conversion_lookup AS cl
      ON (h.id_lead = cl.id_lead)
      AND (h.business_context = cl.business_context)
      AND (h.supply_source = cl.supply_source)
)

SELECT 
  *
FROM 
  aux_tab
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_lead_ebdb, id_house, business_context, funnel_step, business_event ORDER BY ts_event_adjusted) = 1 