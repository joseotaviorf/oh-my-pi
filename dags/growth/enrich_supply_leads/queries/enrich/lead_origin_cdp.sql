WITH cdp_utms AS (
  SELECT
    COALESCE(
      CAST(GET_JSON_OBJECT(user_properties, '$.lead_id') AS BIGINT),
      CAST(GET_JSON_OBJECT(event_properties, '$.formfield_lead_id') AS BIGINT)
    ) AS id_lead_ebdb,
    egw_utm_source,
    egw_utm_medium,
    egw_utm_campaign,
    egw_utm_term,
    egw_utm_content,
    GET_JSON_OBJECT(user_properties, '$.egw_referrer_domain') AS egw_referrer_domain
  FROM
    datalake_cdp_clean.user_tracking
  WHERE
    event_name IN ('lead_form_submitted', 'price_suggestion_form_submitted', 'price_suggestion_sale_form_submitted', 
      'intro_page_viewed', 'property_details_page_viewed', 'property_address_details_page_viewed', 'rent_pricing_new_listing_page_viewed', 'sale_pricing_new_listing_page_viewed',
      'rent_pricing_new_listing_form_submitted', 'sale_pricing_new_listing_form_submitted', 'photo_scheduling_page_viewed', 'photo_scheduling_form_submitted')
    AND COALESCE(
      CAST(GET_JSON_OBJECT(user_properties, '$.lead_id') AS BIGINT),
      CAST(GET_JSON_OBJECT(event_properties, '$.formfield_lead_id') AS BIGINT)
    ) IS NOT NULL
    AND MAKE_DATE(year, month, day) >= DATE('{load_start_date}') - INTERVAL 60 DAYS
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY COALESCE(
      CAST(GET_JSON_OBJECT(user_properties, '$.lead_id') AS BIGINT),
      CAST(GET_JSON_OBJECT(event_properties, '$.formfield_lead_id') AS BIGINT)
    )
    ORDER BY ts_event
  ) = 1
),
lead_origin_rene_descartes AS (
  SELECT
    hl.id AS id_lead,
    hl.id_lead_ebdb,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.affiliateType') AS STRING) AS affiliate_type,
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
    COALESCE(formfield_lead_uuid, id_firestore) AS id_lead,
    id_lead AS id_lead_ebdb,
    IF(utm_campaign == '', '-1', utm_campaign) AS campaign,
    IF(utm_medium == '', '-1', utm_medium) AS medium,
    IF(utm_source == '', '-1', utm_source) AS source,
    IF(utm_content == '', '-1', utm_content) AS content,
    IF(utm_term == '', '-1', utm_term) AS term,
    IF(city == '', '-1', city) AS city,
    IF(platform == '', '-1', platform) AS platform,
    ts_event
  FROM
    datalake_amplitude_lead.lead_origin AS lo
  WHERE
    DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  QUALIFY ROW_NUMBER() OVER(PARTITION BY COALESCE(formfield_lead_uuid, id_firestore, id_lead) ORDER BY ts_event) = 1
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
    COALESCE(cdp.egw_utm_campaign, a.campaign, a2.campaign, ia.utm_campaign) AS campaign,
    COALESCE(
      cdp.egw_utm_medium,
      CASE
        WHEN cdp.egw_referrer_domain IN ('www.google.com', 'www.google.com.br', 'www.bing.com',
          'br.search.yahoo.com', 'r.search.yahoo.com', 'search.brave.com', 'duckduckgo.com') THEN 'seo'
      END,
      a.medium,
      a2.medium,
      ia.utm_medium
    ) AS medium,
    COALESCE(
      cdp.egw_utm_source,
      CASE
        WHEN cdp.egw_referrer_domain IN ('www.google.com', 'www.google.com.br') THEN 'google'
        WHEN cdp.egw_referrer_domain = 'www.bing.com' THEN 'bing'
        WHEN cdp.egw_referrer_domain IN ('br.search.yahoo.com', 'r.search.yahoo.com') THEN 'yahoo'
        WHEN cdp.egw_referrer_domain = 'search.brave.com' THEN 'brave'
        WHEN cdp.egw_referrer_domain = 'duckduckgo.com' THEN 'duckduckgo'
      END,
      a.source,
      a2.source,
      ia.utm_source
    ) AS source,
    COALESCE(cdp.egw_utm_content, a.content, a2.content, ia.utm_content) AS content,
    COALESCE(cdp.egw_utm_term, a.term, a2.term, ia.utm_term) AS term,
    r.ops_agent,
    r.ops_partner,
    r.application,
    COALESCE(r.city, a.city, a2.city) AS city,
    r.landing_page,
    r.ops_approach,
    r.ops_contact_medium,
    COALESCE(IF(r.platform == '', NULL, r.platform), a.platform, a2.platform) AS platform,
    r.lead_type,
    r.detailed_route,
    r.original_lead,
    ia.id_task,
    r.id_ai_core_session,
    ia.id_session AS id_chat_session,
    r.gclid,
    r.fbclid,
    ia.ctwa_clid,
    ia.quinto_andar_phone_number,
    ia.id_source_ctwa,
    ia.url_source_ctwa,
    ia.type_source_ctwa,
    NVL2(cdp.egw_utm_campaign, 'cdp', NVL2(a.campaign, 'amplitude', NVL2(a2.campaign, 'amplitude', NVL2(ia.utm_campaign, 'facebook_api', 'lost_tracking')))) AS database_tracking_campaign,
    NVL2(cdp.egw_utm_medium, 'cdp', NVL2(cdp.egw_referrer_domain, 'cdp_referrer', NVL2(a.medium, 'amplitude', NVL2(a2.medium, 'amplitude', NVL2(ia.utm_medium, 'facebook_api', 'lost_tracking'))))) AS database_tracking_medium,
    NVL2(cdp.egw_utm_source, 'cdp', NVL2(cdp.egw_referrer_domain, 'cdp_referrer', NVL2(a.source, 'amplitude', NVL2(a2.source, 'amplitude', NVL2(ia.utm_source, 'facebook_api', 'lost_tracking'))))) AS database_tracking_source,
    NVL2(cdp.egw_utm_content, 'cdp', NVL2(a.content, 'amplitude', NVL2(a2.content, 'amplitude', NVL2(ia.utm_content, 'facebook_api', 'lost_tracking')))) AS database_tracking_content,
    NVL2(cdp.egw_utm_term, 'cdp', NVL2(a.term, 'amplitude', NVL2(a2.term, 'amplitude', NVL2(ia.utm_term, 'facebook_api', 'lost_tracking')))) AS database_tracking_term,
    NVL2(r.ctwa_clid, 'rene_descartes', NVL2(ia.ctwa_clid, 'sauron', 'lost_tracking')) AS database_tracking_ctwa,
    r.ts_event
  FROM
    lead_origin_rene_descartes AS r
  LEFT JOIN
    cdp_utms AS cdp
      ON r.id_lead_ebdb = cdp.id_lead_ebdb
  LEFT JOIN
    lead_origin_amplitude AS a
      ON (a.id_lead = r.id_lead)
  LEFT JOIN
    lead_origin_amplitude AS a2
      ON (r.id_lead_ebdb = a2.id_lead_ebdb)
  LEFT JOIN
    affiliate_type_fix AS atf
      ON (r.id_lead = atf.id_lead)
  LEFT JOIN
    inbound_leads AS ia
      ON ia.id_lead_ebdb = r.id_lead_ebdb
)
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
