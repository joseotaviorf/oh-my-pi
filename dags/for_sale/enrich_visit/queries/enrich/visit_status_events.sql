WITH request_logs as (
  SELECT
    id_trace,
    visit_code,
    host,
    channel,
    ts_request
  FROM
    datalake_request_logging_clean.visits
  WHERE
    DATE(ts_request) >= DATE('2026-04-29')
    AND status_code = 200
),
visit_aud AS (
  SELECT
    va.id_visit,
    va.id_agent AS id_user_agent,
    u.id_agent AS id_agent,
    va.ts_visit,
    ure.ts_revision AS ts_created
  FROM
    datalake_ebdb_clean.visit_aud AS va
  LEFT JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON va.rev = ure.id
  LEFT JOIN
    datalake_ebdb_clean.user AS u
      ON va.id_agent = u.id
),
vsl AS (
  SELECT
    vsl.id_visit_status_log,
    vsl.id_visit,
    vsl.id_schedule,
    vsl.id_author_user,
    v.id_visitor,
    v.id_agent,
    v.id_house,
    rl.id_trace,
    v.code AS visit_code,
    v.business_context,
    vsl.author_user_type,
    CASE
      WHEN vsl.channel IN ('AGENT_NATIVE', 'AGENT_PWA') THEN 'AGENT'
      WHEN vsl.channel IN ('OWNER_NATIVE', 'OWNER_PWA') THEN 'SUPPLY'
      WHEN vsl.channel IN ('TENANT_NATIVE', 'TENANT_PWA') THEN 'DEMAND'
      ELSE NULL
    END AS author_user_role_enriched,
    COALESCE(vsl.author_user_role, author_user_role_enriched) AS author_user_role,
    vsl.on_behalf_of,
    CASE
      WHEN rl.channel = 'qa_app' THEN 'NATIVE'
      ELSE UPPER(rl.channel)
    END AS log_channel,
    CASE -- We will hard coded the channels when we do not have the channel in the request logging since the old channel/host data has fixed channels
      WHEN rl.host = 'wall_e' THEN CONCAT(COALESCE(log_channel, 'NATIVE'), '_WALLE')
      WHEN rl.host = 'concierge' THEN CONCAT(COALESCE(log_channel, 'WHATSAPP'), '_CONCIERGE')
      WHEN rl.host = 'sonia' THEN CONCAT(COALESCE(log_channel, 'WHATSAPP'), '_SONIA')
      WHEN rl.host = 'isaias' THEN CONCAT(COALESCE(log_channel, 'WHATSAPP'), '_ISAIAS')
      ELSE NULLIF(CONCAT_WS('_', log_channel, UPPER(rl.host)), '') -- Keep the channel_host as is for new hosts with channel field filled
    END AS host_unified,
    CASE
      WHEN vsl.channel IN ('NATIVE_WALLE', 'WHATSAPP_CONCIERGE', 'WHATSAPP_SONIA') THEN CONCAT('CONVERSATIONAL - ', vsl.channel) -- Unified the old IA channels with the new unified channels
      WHEN vsl.channel = 'CONVERSATIONAL' THEN CONCAT_WS(' - ', vsl.channel, host_unified) -- Enrich the channel with the host unified
      ELSE vsl.channel -- Keep the channel as is for other channels (not conversational)
    END AS channel,
    vsl.application_source,
    vsl.reason,
    vsl.event_type,
    ROW_NUMBER() OVER(PARTITION BY vsl.id_visit_status_log ORDER BY rl.ts_request DESC) AS ranking_last_request_logging,
    vsl.ts_created,
    v.ts_created AS ts_visit_created,
    vsl.ts_updated
  FROM
    datalake_ebdb_clean.visit_status_log AS vsl
  JOIN
    datalake_ebdb_clean.visit AS v
      ON v.id = vsl.id_visit
  LEFT JOIN
    request_logs AS rl
      ON rl.visit_code = v.code
      AND ABS(DATE_DIFF(SECOND, rl.ts_request, vsl.ts_created)) < 1
      AND vsl.channel = 'CONVERSATIONAL'
  WHERE
    DATE(v.ts_created) >= '2024-11-01'
),
vsl_enriched AS (
  SELECT
    ROW_NUMBER() OVER(PARTITION BY vsl.id_visit ORDER BY vsl.ts_created ASC) AS ranking,
    CONCAT(vsl.id_visit_status_log,'R',ranking) AS id_visit_status_events,
    vsl.id_visit_status_log,
    vsl.id_visit,
    vsl.id_schedule,
    vsl.id_author_user,
    vsl.id_visitor,
    vsl.id_agent,
    vsl.id_house,
    COALESCE(hl.id_house_listing, -1) AS id_house_listing,
    lh.id_user AS id_owner,
    -1 AS id_rent_flow,
    'NA' AS id_sale_flow, --esse id é um coalesce
    -1 AS id_fup_details,
    vsl.id_trace,
    vbm.sk_broker_supply,
    vbm.sk_broker_demand,
    vbm.id_company_supply,
    vbm.id_company_demand,
    lh.uuid_company AS uuid_company_supply,
    vsl.visit_code,
    vsl.business_context,
    vsl.event_type,
    vsl.author_user_type,
    vsl.author_user_role,
    vsl.on_behalf_of,
    vsl.channel,
    vsl.application_source,
    vsl.reason,
    vbm.partner_3p_supply,
    vbm.partner_3p_demand,
    hl.country_code,
    vbm.is_3p_supply,
    vbm.is_3p_demand,
    vbm.is_3p_lead_gen,
    vbm.has_3p_access_control,
    CASE
      WHEN ROW_NUMBER() OVER(PARTITION BY vsl.id_visit ORDER BY vsl.ts_created DESC) == 1 THEN TRUE
      ELSE FALSE
    END AS is_visit_last_event,
    vsl.ts_created,
    vsl.ts_updated
  FROM
    vsl
  INNER JOIN
    datalake_ebdb_listing.house lh
      ON lh.id = vsl.id_house
  LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON vsl.id_house = hl.id_house
      AND DATE(vsl.ts_visit_created) >= DATE(hl.ts_listing_version_start)
      AND (DATE(vsl.ts_visit_created) < DATE(hl.ts_listing_version_end) OR hl.ts_listing_version_end IS NULL)
  LEFT JOIN
    datalake_visit.visit_business_model AS vbm
      ON vsl.id_visit = vbm.id_visit
  WHERE
    vsl.ranking_last_request_logging = 1
),
vsl_agent AS (
  SELECT
    ve.ranking,
    ve.id_visit_status_events,
    ve.id_visit_status_log,
    ve.id_visit,
    ve.id_schedule,
    ve.id_author_user,
    ve.id_visitor,
    ve.id_agent,
    va.id_user_agent AS id_user_agent_by_event,
    ve.id_house,
    ve.id_house_listing,
    ve.id_owner,
    ve.id_rent_flow,
    ve.id_sale_flow,
    ve.id_fup_details,
    ve.id_trace,
    ve.sk_broker_supply,
    ve.sk_broker_demand,
    ve.id_company_supply,
    ve.id_company_demand,
    ve.uuid_company_supply,
    ve.visit_code,
    ve.business_context,
    ve.event_type,
    ve.author_user_type,
    ve.author_user_role,
    ve.on_behalf_of,
    ve.channel,
    ve.application_source,
    ve.reason,
    ve.partner_3p_supply,
    ve.partner_3p_demand,
    ve.country_code,
    ve.is_3p_supply,
    ve.is_3p_demand,
    ve.is_3p_lead_gen,
    ve.has_3p_access_control,
    ve.is_visit_last_event,
    ve.ts_created,
    ve.ts_updated,
    ROW_NUMBER() OVER(PARTITION BY ve.id_visit_status_events ORDER BY va.ts_created DESC) AS ranking_last_visit_aud
  FROM
    vsl_enriched AS ve
  LEFT JOIN
    visit_aud AS va
      ON ve.id_visit = va.id_visit
      AND DATE_TRUNC('SECOND', ve.ts_created) >= DATE_ADD(SECOND, -1, DATE_TRUNC('SECOND', va.ts_created))
)
SELECT
  ranking,
  id_visit_status_events,
  id_visit_status_log,
  id_visit,
  id_schedule,
  id_author_user,
  id_visitor,
  id_agent,
  id_user_agent_by_event,
  id_house,
  id_house_listing,
  id_owner,
  id_rent_flow,
  id_sale_flow,
  id_fup_details,
  id_trace,
  sk_broker_supply,
  sk_broker_demand,
  id_company_supply,
  id_company_demand,
  uuid_company_supply,
  visit_code,
  business_context,
  event_type,
  author_user_type,
  author_user_role,
  on_behalf_of,
  channel,
  application_source,
  reason,
  partner_3p_supply,
  partner_3p_demand,
  country_code,
  is_3p_supply,
  is_3p_demand,
  is_3p_lead_gen,
  has_3p_access_control,
  is_visit_last_event,
  ts_created,
  ts_updated
FROM
  vsl_agent
WHERE
  ranking_last_visit_aud = 1
