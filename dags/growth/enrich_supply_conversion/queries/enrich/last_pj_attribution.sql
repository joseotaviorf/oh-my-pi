SELECT 
  cs.id_entity AS id_house,
  cs.id_lead,
  cs.id_user_registrant,
  cs.business_context,
  u.email,
  oa.ops_agent,
  oa.ops_objective,
  oa.ops_partner,
  oa.ops_approach,
  oa.ops_contact_medium,
  cs.ts_event
FROM 
  datalake_supply_flows.conversion_staging AS cs
LEFT JOIN 
  datalake_supply_flows.operations_agents AS oa
    ON (cs.id_user_registrant = oa.id_user)
LEFT JOIN 
  datalake_ebdb_clean.user AS u
    ON (u.id = cs.id_user_registrant)
WHERE 
  cs.source = 'PJ'
    AND cs.status = 'Agendado'
QUALIFY ROW_NUMBER() OVER (PARTITION BY cs.id_entity, cs.business_context ORDER BY cs.rev DESC) = 1