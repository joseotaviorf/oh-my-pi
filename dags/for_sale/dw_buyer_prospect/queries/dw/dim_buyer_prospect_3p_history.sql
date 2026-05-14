WITH base AS (
  SELECT
    CONCAT(v.id_visit, 1) AS id_buyer_prospect_event,
    v.id_visitor AS id_buyer,
    NULL AS id_lead_referral,
    v.id_visit AS id_visit,
    v.sk_broker_demand AS sk_broker,
    CASE
      WHEN v.business_model LIKE '%3P_DEMAND%' THEN '3P_DEMAND'
      WHEN v.business_model LIKE '%3P_LEAD_GEN%' THEN '3P_LEAD_GEN'
    END AS demand_type,
    'VISIT' AS event_source,
    'VISIT_REQUESTED' AS event_type,
    'AGENT' AS trigger_actor,
    v.ts_created AS ts_event_start
  FROM
    datalake_visit.visits AS v
  WHERE
    DATE(v.ts_created) < DATE '2025-10-07'
    AND (v.business_model LIKE '%3P_DEMAND%' OR v.business_model LIKE '%3P_LEAD_GEN%')

  UNION ALL

  SELECT
    CONCAT(bc.id, 2) AS id_buyer_prospect_event,
    COALESCE(u.id, -1) AS id_buyer,
    CASE
      WHEN bce.event_entity_name = 'AGENT_REFERRAL' THEN bce.id_event_entity
    END AS id_lead_referral,
    CASE
      WHEN bce.event_entity_name = 'VISIT' THEN bce.id_event_entity
    END AS id_visit,
    cb.sk_broker,
    CASE
      WHEN bc.type = '1P' THEN '3P_LEAD_GEN'
      WHEN bc.type = '3P' THEN '3P_DEMAND'
    END AS demand_type,
    'BUYER_COMPANY_RELATION' AS event_source,
    bce.event_type,
    bce.trigger_actor,
    bc.ts_started AS ts_event_start
  FROM
    datalake_rede_platform_clean.buyer_company AS bc
  LEFT JOIN
    datalake_rede_platform_clean.buyer_company_event AS bce
      ON bce.id = bc.id_buyer_company_event
  LEFT JOIN
    core_brokers.brokers AS cb
      ON bc.uuid_company = cb.uuid_company
  LEFT JOIN
    datalake_person.person_sks AS p
      ON bc.uuid_person = p.uuid_person
  LEFT JOIN
    datalake_ebdb_clean.user AS u
      ON bc.uuid_person = u.uuid_person
  WHERE
    bce.event_type = 'VISIT_REQUESTED'
),
ordered_base AS (
  SELECT
    b.id_buyer_prospect_event,
    b.id_buyer,
    b.sk_broker,
    b.id_lead_referral,
    b.id_visit,
    b.demand_type,
    b.event_source,
    b.event_type,
    b.trigger_actor,
    b.ts_event_start,
    ROW_NUMBER() OVER (PARTITION BY b.id_buyer, b.demand_type ORDER BY b.ts_event_start, b.id_buyer_prospect_event) AS rn_episode,
    LAG(b.ts_event_start) OVER (PARTITION BY b.id_buyer, b.demand_type ORDER BY b.ts_event_start, b.id_buyer_prospect_event) AS prev_ts_start
  FROM
    base AS b
),
classified AS (
  SELECT
    ob.id_buyer_prospect_event,
    ob.id_buyer,
    ob.id_visit,
    ob.sk_broker,
    ob.demand_type,
    ob.event_source,
    ob.event_type,
    ob.trigger_actor,
    ob.ts_event_start,
    CASE
      WHEN ob.rn_episode = 1 THEN 'NBP'
      WHEN ob.prev_ts_start IS NOT NULL AND DATEDIFF(TO_DATE(ob.ts_event_start), TO_DATE(ob.prev_ts_start)) >= 90
        THEN 'RBP'
    END AS buyer_prospect_type
  FROM
    ordered_base AS ob
),
prospect_windows AS (
  SELECT
    c.id_buyer_prospect_event,
    c.id_buyer,
    c.id_visit,
    c.sk_broker,
    c.demand_type,
    c.buyer_prospect_type,
    c.event_source,
    c.event_type,
    c.trigger_actor,
    ROW_NUMBER() OVER (PARTITION BY c.id_buyer, c.demand_type ORDER BY c.ts_event_start, c.id_buyer_prospect_event) AS version,
    c.ts_event_start AS ts_started,
    LEAD(c.ts_event_start) OVER (PARTITION BY c.id_buyer, c.demand_type ORDER BY c.ts_event_start, c.id_buyer_prospect_event) AS ts_ended
  FROM
    classified AS c
  WHERE
    c.buyer_prospect_type IS NOT NULL
)
SELECT
  CONCAT(pw.id_buyer, 0, pw.version) AS sk_buyer_prospect,
  pw.id_buyer AS sk_buyer,
  COALESCE(pw.id_visit, -1) AS sk_visit,
  pw.sk_broker,
  pw.demand_type,
  pw.buyer_prospect_type,
  CASE
    WHEN pw.buyer_prospect_type = 'NBP' THEN 'New Buyer Prospect'
    WHEN pw.buyer_prospect_type = 'RBP' THEN 'Recovery Buyer Prospect'
  END AS buyer_prospect_type_long,
  pw.event_source,
  pw.event_type,
  pw.trigger_actor,
  pw.version,
  pw.ts_ended IS NULL AS is_current,
  pw.ts_started,
  pw.ts_ended,
  CURRENT_TIMESTAMP AS ts_load
FROM
  prospect_windows AS pw
WHERE
  pw.id_buyer IS NOT NULL