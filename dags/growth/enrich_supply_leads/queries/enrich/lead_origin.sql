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
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.originalLead') AS BIGINT) AS original_lead,
    amd.ts_created AS ts_event
  FROM datalake_rene_descartes_clean.house_lead AS hl
  LEFT JOIN datalake_rene_descartes_clean.acquisition_misc_data AS amd
    ON hl.id_acquisition = amd.id
  WHERE DATE(amd.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

),
-- Rule to fix affiliate type, we get the original affiliate type
affiliate_type_fix AS (
  SELECT 
    lo_base.id_lead, 
    lo_fix.affiliate_type AS first_affiliate_type
  FROM lead_origin_rene_descartes AS lo_base
  JOIN lead_origin_rene_descartes AS lo_fix
    ON (lo_base.original_lead = lo_fix.id_lead_ebdb)
  WHERE lo_base.affiliate_type IS NULL
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
  FROM datalake_amplitude_lead.lead_origin
  WHERE DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  QUALIFY ROW_NUMBER() OVER(PARTITION BY COALESCE(formfield_lead_uuid, id_firestore, id_lead) ORDER BY ts_event) = 1 -- Getting the first event
),

mid_table AS (
  SELECT 
    r.id_lead AS id_lead,
    r.id_lead_ebdb AS id_lead_ebdb,
    COALESCE(r.affiliate_type, atf.first_affiliate_type) AS affiliate_type,
    COALESCE(r.campaign, a.campaign, a2.campaign) AS campaign,
    COALESCE(r.medium, a.medium, a2.medium) AS medium,  
    COALESCE(r.source, a.source, a2.source) AS source,
    COALESCE(r.content, a.content, a2.content) AS content,
    COALESCE(r.term, a.term, a2.term) AS term,
    r.ops_agent,
    r.ops_partner,
    r.application,
    COALESCE(r.city, a.city, a2.city) AS city,
    r.landing_page,
    r.ops_approach,
    r.ops_contact_medium,
    COALESCE(r.platform, a.platform, a2.platform) AS platform,
    r.lead_type,
    r.original_lead,
    -- We're tracking how database is the source of our UTMs
    NVL2(r.campaign, 'rene_descartes', NVL2(a.campaign, 'amplitude', NVL2(a2.campaign, 'amplitude', 'lost_tracking'))) AS database_tracking_campaign,
    NVL2(r.medium, 'rene_descartes', NVL2(a.medium, 'amplitude', NVL2(a2.medium, 'amplitude', 'lost_tracking'))) AS database_tracking_medium,
    NVL2(r.source, 'rene_descartes', NVL2(a.source, 'amplitude', NVL2(a2.source, 'amplitude', 'lost_tracking'))) AS database_tracking_source,
    NVL2(r.content, 'rene_descartes', NVL2(a.content, 'amplitude', NVL2(a2.content, 'amplitude', 'lost_tracking'))) AS database_tracking_content,
    NVL2(r.term, 'rene_descartes', NVL2(a.term, 'amplitude', NVL2(a2.term, 'amplitude', 'lost_tracking'))) AS database_tracking_term,
    COALESCE(r.ts_event, a.ts_event) AS ts_event
  FROM lead_origin_rene_descartes AS r
  LEFT JOIN lead_origin_amplitude AS a
    ON (a.id_lead = r.id_lead)
  LEFT JOIN lead_origin_amplitude AS a2
    ON (r.id_lead_ebdb = a2.id_lead_ebdb)
  LEFT JOIN affiliate_type_fix AS atf
    ON (r.id_lead = atf.id_lead)
)

-- Hard rules
SELECT 
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