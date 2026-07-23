WITH lead_origin_rene_descartes AS (
  -- In this CTE we extract all taxonomy data available in Rene Descartes
  SELECT
    hl.id AS id_lead,
    hl.id_lead_ebdb,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.affiliateType') AS STRING) AS affiliate_type,
    NULLIF(CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmCampaign') AS STRING), '') AS campaign,
    NULLIF(CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmMedium') AS STRING), '') AS medium,
    NULLIF(CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmSource') AS STRING), '') AS source,
    NULLIF(CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmContent') AS STRING), '') AS content,
    NULLIF(CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmTerm') AS STRING), '') AS term,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.team') AS STRING) AS ops_agent,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.company') AS STRING) AS ops_partner,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.origin') AS STRING) AS application,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.cidade') AS STRING) AS city,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.referrer') AS STRING) AS landing_page,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.contactType') AS STRING) AS ops_approach,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.contactChannel') AS STRING) AS ops_contact_medium,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.platform') AS STRING) AS platform,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.type') AS STRING) AS lead_type,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.detailedRoute') AS STRING) AS detailed_route,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.originalLead') AS BIGINT) AS original_lead,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.taskId') AS STRING) AS id_task,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.gclid') AS STRING) AS gclid,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.fbclid') AS STRING) AS fbclid,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.ctwaClid') AS STRING) AS ctwa_clid,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.aiCoreSessionId') AS STRING) AS id_ai_core_session,
    amd.ts_created AS ts_event
  FROM
    datalake_rene_descartes_clean.house_lead AS hl
  LEFT JOIN
    datalake_rene_descartes_clean.acquisition_misc_data AS amd
      ON hl.id_acquisition = amd.id
  WHERE
    DATE(amd.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
-- Rule to fix affiliate type, we get the original affiliate type
affiliate_type_fix AS (
  SELECT
    lo_base.id_lead,
    lo_fix.affiliate_type AS first_affiliate_type
  FROM
    lead_origin_rene_descartes AS lo_base
  JOIN
    lead_origin_rene_descartes AS lo_fix
      ON (lo_base.original_lead = lo_fix.id_lead_ebdb)
  WHERE
    lo_base.affiliate_type IS NULL
    AND lo_fix.affiliate_type IS NOT NULL
),
lead_origin_amplitude AS (
  SELECT
    id_lead AS id_lead_ebdb,
    NULLIF(utm_campaign, '') AS campaign,
    NULLIF(utm_medium, '') AS medium,
    NULLIF(utm_source, '') AS source,
    NULLIF(utm_content, '') AS content,
    NULLIF(utm_term, '') AS term,
    NULLIF(city, '') AS city,
    NULLIF(platform, '') AS platform,
    ts_event
  FROM
    datalake_amplitude_lead.lead_origin AS lo
  WHERE
    DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_lead ORDER BY ts_event) = 1
),
inbound_leads AS (
  SELECT
    ia.id_lead_ebdb,
    ia.id_session,
    ia.id_task,
    ia.id_source_ctwa,
    ia.quinto_andar_phone_number,
    ia.ctwa_clid,
    ia.url_source_ctwa,
    ia.type_source_ctwa,
    fm.utm_campaign,
    fm.utm_term,
    fm.utm_content,
    fm.origin AS utm_source,
    'whatsapp' AS utm_medium
  FROM
    datalake_supply_flows.inbound_attribution AS ia
  LEFT JOIN
    datalake_growth_media_platform.facebook_metrics AS fm
      ON ia.id_source_ctwa = fm.id_ad
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY ia.id_lead_ebdb ORDER BY fm.dt_cost DESC) = 1
),
mid_table AS (
  SELECT
    r.id_lead AS id_lead,
    r.id_lead_ebdb AS id_lead_ebdb,
    COALESCE(r.affiliate_type, atf.first_affiliate_type) AS affiliate_type,
    COALESCE(r.campaign, a.campaign, inbound_leads.utm_campaign) AS campaign,
    COALESCE(r.medium, a.medium, inbound_leads.utm_medium) AS medium,
    COALESCE(r.source, a.source, inbound_leads.utm_source) AS source,
    COALESCE(r.content, a.content, inbound_leads.utm_content) AS content,
    COALESCE(r.term, a.term, inbound_leads.utm_term) AS term,
    r.ops_agent,
    r.ops_partner,
    r.application,
    COALESCE(r.city, a.city) AS city,
    r.landing_page,
    r.ops_approach,
    r.ops_contact_medium,
    COALESCE(IF(r.platform == '', NULL, r.platform), a.platform) AS platform,
    r.lead_type,
    r.detailed_route,
    r.original_lead,
    inbound_leads.id_task,
    r.id_ai_core_session,
    inbound_leads.id_session AS id_chat_session,
    r.gclid,
    r.fbclid,
    inbound_leads.ctwa_clid,
    inbound_leads.quinto_andar_phone_number,
    inbound_leads.id_source_ctwa,
    inbound_leads.url_source_ctwa,
    inbound_leads.type_source_ctwa,
    -- We're tracking how database is the source of our UTMs
    NVL2(r.campaign, 'rene_descartes', NVL2(a.campaign, 'amplitude', NVL2(inbound_leads.utm_campaign, 'facebook_api', 'lost_tracking'))) AS database_tracking_campaign,
    NVL2(r.medium, 'rene_descartes', NVL2(a.medium, 'amplitude', NVL2(inbound_leads.utm_medium, 'facebook_api', 'lost_tracking'))) AS database_tracking_medium,
    NVL2(r.source, 'rene_descartes', NVL2(a.source, 'amplitude', NVL2(inbound_leads.utm_source, 'facebook_api', 'lost_tracking'))) AS database_tracking_source,
    NVL2(r.content, 'rene_descartes', NVL2(a.content, 'amplitude', NVL2(inbound_leads.utm_content, 'facebook_api', 'lost_tracking'))) AS database_tracking_content,
    NVL2(r.term, 'rene_descartes', NVL2(a.term, 'amplitude', NVL2(inbound_leads.utm_term, 'facebook_api', 'lost_tracking'))) AS database_tracking_term,
    NVL2(r.ctwa_clid, 'rene_descartes', NVL2(inbound_leads.ctwa_clid, 'sauron', 'lost_tracking')) AS database_tracking_ctwa,
    COALESCE(r.ts_event, a.ts_event) AS ts_event
  FROM
    lead_origin_rene_descartes AS r
  LEFT JOIN
    lead_origin_amplitude AS a
      ON (r.id_lead_ebdb = a.id_lead_ebdb)
  LEFT JOIN
    affiliate_type_fix AS atf
      ON (r.id_lead = atf.id_lead)
  LEFT JOIN
    inbound_leads
      ON inbound_leads.id_lead_ebdb = r.id_lead_ebdb
)
-- Hard rules
SELECT DISTINCT
  id_lead,
  id_lead_ebdb,
  SF_NORMALIZE_STRING(affiliate_type) AS affiliate_type,
  campaign,
  SF_NORMALIZE_STRING(medium) AS medium,
  SF_NORMALIZE_STRING(source) AS source,
  SF_NORMALIZE_STRING(content) AS content,
  SF_NORMALIZE_STRING(term) AS term,
  SF_NORMALIZE_STRING(ops_agent) AS ops_agent,
  CASE
    WHEN ops_agent = 'CAPTA_AI' THEN 'acquisition'
    WHEN ops_agent IS NOT NULL THEN 'conversion'
    ELSE NULL
  END AS ops_objective,
  SF_NORMALIZE_STRING(ops_partner) AS ops_partner,
  SF_NORMALIZE_STRING(application) AS application,
  city,
  SF_NORMALIZE_STRING(landing_page) AS landing_page,
  -- If we have a original lead, we mark as reprocessed
  IF(original_lead IS NOT NULL, 'automatically_reprocessed', NULL) AS reprocessed,
  SF_NORMALIZE_STRING(ops_approach) AS ops_approach,
  SF_NORMALIZE_STRING(ops_contact_medium) AS ops_contact_medium,
  SF_NORMALIZE_STRING(platform) AS platform,
  SF_NORMALIZE_STRING(lead_type) AS lead_type,
  SF_NORMALIZE_STRING(detailed_route) AS detailed_route,
  gclid,
  fbclid,
  ctwa_clid,
  id_task,
  id_chat_session,
  id_ai_core_session,
  REGEXP_EXTRACT(quinto_andar_phone_number, '[0-9]+', 0) AS quinto_andar_phone_number,
  id_source_ctwa,
  url_source_ctwa,
  type_source_ctwa,
  original_lead,
  database_tracking_campaign,
  database_tracking_medium,
  database_tracking_source,
  database_tracking_content,
  database_tracking_term,
  database_tracking_ctwa,
  ts_event,
  CURRENT_TIMESTAMP AS ts_load
FROM
  mid_table
