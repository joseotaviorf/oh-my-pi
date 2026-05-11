WITH request_logs as (
  SELECT
    visit_code,
    host,
    ts_request
  FROM
    datalake_request_logging_clean.visits
  WHERE
    ts_request::date >= '2026-04-29'
    AND status_code = 200
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
    v.code AS visit_code,
    v.business_context,
    vsl.author_user_type,
    vsl.author_user_role,
    vsl.on_behalf_of,
    CASE -- We will hard coded the channels until we have the channel in the request logging since the current data has fixed channels
      WHEN rl.host = 'wall_e' THEN 'NATIVE_WALLE'
      WHEN rl.host = 'concierge' THEN 'WHATSAPP_CONCIERGE'
      WHEN rl.host = 'sonia' THEN 'WHATSAPP_SONIA'
      WHEN rl.host = 'isaias' THEN 'WHATSAPP_ISAIAS'
      ELSE UPPER(rl.host)
    END AS host_unified,
    CASE
      WHEN vsl.channel IN ('NATIVE_WALLE', 'WHATSAPP_CONCIERGE', 'WHATSAPP_SONIA') THEN CONCAT('CONVERSATIONAL - ', vsl.channel) -- Unified the old IA channels with the new unified channels
      WHEN vsl.channel = 'CONVERSATIONAL' THEN CONCAT_WS(' - ', vsl.channel, host_unified) -- Enrich the channel with the host unified
      ELSE vsl.channel -- Keep the channel as is for other channels (not conversational)
    END AS channel,
    vsl.application_source,
    vsl.reason,
    vsl.event_type,
    ROW_NUMBER() OVER(PARTITION BY vsl.id_visit ORDER BY vsl.ts_created ASC) AS ranking,
    CASE
      WHEN ROW_NUMBER() OVER(PARTITION BY vsl.id_visit ORDER BY vsl.ts_created DESC) == 1 THEN TRUE
      ELSE FALSE
    END AS is_visit_last_event,
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
)
  SELECT
    CONCAT(vsl.id_visit_status_log,'R',vsl.ranking) AS id_visit_status_events,
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
    vbm.sk_broker_supply,
    vbm.sk_broker_demand,
    vbm.id_company_supply,
    vbm.id_company_demand,
    lh.uuid_company AS uuid_company_supply,
    vsl.visit_code,
    vsl.business_context,
    vsl.event_type,
    vsl.ranking,
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
    vsl.is_visit_last_event,
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
