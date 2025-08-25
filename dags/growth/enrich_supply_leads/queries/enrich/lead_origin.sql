WITH lead_origin_rene_descartes AS (
  -- In this CTE we extract all taxonomy data available in Rene Descartes
  SELECT
    hl.id AS id_lead,
    hl.id_lead_ebdb,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.affiliateType') AS STRING) AS affiliate_type,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmCampaign') AS STRING) AS campaign,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmMedium') AS STRING) AS medium,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmSource') AS STRING) AS source,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmContent') AS STRING) AS content,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmTerm') AS STRING) AS term,
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
  -- Here, I collect data from Amplitude
  SELECT
    COALESCE(formfield_lead_uuid, id_firestore) AS id_lead, -- This coalesce is necessary because we have two different keys in Amplitude
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
  QUALIFY ROW_NUMBER() OVER(PARTITION BY COALESCE(formfield_lead_uuid, id_firestore, id_lead) ORDER BY ts_event) = 1 -- Works if formfield_lead_uuid is a NULL
),
phone_number AS (
  SELECT DISTINCT
    id_task,
    twilio_phone_number as quinto_andar_phone_number,
    id_source_ctwa,
    url_source_ctwa,
    type_source_ctwa
  FROM
    datalake_customer_support.chats
  UNION ALL
  SELECT DISTINCT
    id_task,
    CASE
      WHEN direction = 'inbound' THEN to_phone_number
      WHEN direction = 'outbound' THEN from_phone_number
    END AS quinto_andar_phone_number,
    NULL AS id_source_ctwa,
    NULL AS url_source_ctwa,
    NULL AS type_source_ctwa
  FROM
    datalake_customer_support.calls
),
click_to_whatsapp_campaigns AS (
  SELECT 
    id_ad,
    utm_campaign,
    utm_term,
    utm_content,
    origin AS utm_source,
    'whatsapp' AS utm_medium
  FROM 
    datalake_growth_media_platform.facebook_metrics
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_ad ORDER BY dt_cost DESC) = 1
),
mid_table AS (
  SELECT
    r.id_lead AS id_lead,
    r.id_lead_ebdb AS id_lead_ebdb,
    COALESCE(r.affiliate_type, atf.first_affiliate_type) AS affiliate_type,
    COALESCE(IF(r.campaign == '', NULL, r.campaign), a.campaign, a2.campaign, ctwac.utm_campaign) AS campaign,
    COALESCE(IF(r.medium == '', NULL, r.medium), a.medium, a2.medium, ctwac.utm_medium) AS medium,
    COALESCE(IF(r.source == '', NULL, r.source), a.source, a2.source, ctwac.utm_source) AS source,
    COALESCE(IF(r.content == '', NULL, r.content), a.content, a2.content, ctwac.utm_content) AS content,
    COALESCE(IF(r.term == '', NULL, r.term), a.term, a2.term, ctwac.utm_term) AS term,
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
    r.id_task,
    r.gclid,
    r.fbclid,
    r.ctwa_clid,
    pn.quinto_andar_phone_number,
    pn.id_source_ctwa,
    pn.url_source_ctwa,
    pn.type_source_ctwa,
    -- We're tracking how database is the source of our UTMs
    NVL2(r.campaign, 'rene_descartes', NVL2(a.campaign, 'amplitude', NVL2(a2.campaign, 'amplitude', NVL2(ctwac.utm_campaign, 'facebook_api', 'lost_tracking')))) AS database_tracking_campaign,
    NVL2(r.medium, 'rene_descartes', NVL2(a.medium, 'amplitude', NVL2(a2.medium, 'amplitude', NVL2(ctwac.utm_medium, 'facebook_api', 'lost_tracking')))) AS database_tracking_medium,
    NVL2(r.source, 'rene_descartes', NVL2(a.source, 'amplitude', NVL2(a2.source, 'amplitude', NVL2(ctwac.utm_source, 'facebook_api', 'lost_tracking')))) AS database_tracking_source,
    NVL2(r.content, 'rene_descartes', NVL2(a.content, 'amplitude', NVL2(a2.content, 'amplitude', NVL2(ctwac.utm_content, 'facebook_api', 'lost_tracking')))) AS database_tracking_content,
    NVL2(r.term, 'rene_descartes', NVL2(a.term, 'amplitude', NVL2(a2.term, 'amplitude', NVL2(ctwac.utm_term, 'facebook_api', 'lost_tracking')))) AS database_tracking_term,
    COALESCE(r.ts_event, a.ts_event) AS ts_event
  FROM
    lead_origin_rene_descartes AS r
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
    phone_number AS pn
      ON (pn.id_task = r.id_task)
  LEFT JOIN
    click_to_whatsapp_campaigns AS ctwac
      ON ctwac.id_ad = pn.id_source_ctwa
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
  ts_event,
  CURRENT_TIMESTAMP AS ts_load
FROM
  mid_table
