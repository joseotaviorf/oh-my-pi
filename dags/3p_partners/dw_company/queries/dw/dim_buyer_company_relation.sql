SELECT
  bc.id AS sk_buyer_company_relation,
  COALESCE(c.sk_company, -1) AS sk_company,
  COALESCE(p.sk_person, -1) AS sk_person,
  COALESCE(u.id, -1) AS sk_user,
  CASE
    WHEN bce.event_entity_name = 'AGENT_REFERRAL' THEN bce.id_event_entity
    ELSE -1
  END AS sk_preferred_fixed_agent,
  CASE
    WHEN bce.event_entity_name = 'VISIT' THEN bce.id_event_entity
    ELSE -1
  END AS sk_visit,
  bc.type AS buyer_company_relation_type,
  bce.application_source,
  CASE
    WHEN bc.type = '1P' THEN '3P_LEAD_GEN'
    WHEN bc.type = '3P' THEN '3P_DEMAND'
  END AS demand_type,
  bce.event_entity_name,
  bce.event_type,
  bce.trigger_actor,
  bc.is_active,
  bc.ts_started AS ts_start,
  bc.ts_finished AS ts_end,
  NOW() AS ts_load
FROM
  datalake_rede_platform_clean.buyer_company AS bc
LEFT JOIN
  datalake_rede_platform_clean.buyer_company_event AS bce
    ON bce.id = bc.id_buyer_company_event
LEFT JOIN
  datalake_company.company_sks AS c
    ON bc.uuid_company = c.uuid_company
LEFT JOIN
  datalake_person.person_sks AS p
    ON bc.uuid_person = p.uuid_person
LEFT JOIN
  datalake_ebdb_clean.user AS u
    ON bc.uuid_person = u.uuid_person