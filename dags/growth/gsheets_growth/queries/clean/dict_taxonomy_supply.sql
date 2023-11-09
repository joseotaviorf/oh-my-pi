SELECT 
  CAST(id AS INTEGER) AS id,
  SF_NORMALIZE_STRING(IF(utm_campaign = '', '-1', utm_campaign)) AS campaign,
  SF_NORMALIZE_STRING(IF(utm_medium = '', '-1', utm_medium)) AS medium,
  SF_NORMALIZE_STRING(IF(utm_source = '', '-1', utm_source)) AS source,
  CAST(is_branded AS BOOLEAN) AS is_branded,
  SF_NORMALIZE_STRING(campaign_intent) AS audience,
  SF_NORMALIZE_STRING(behaviour_type) AS payment_type,
  SF_NORMALIZE_STRING(mkt_medium) AS mkt_medium,
  SF_NORMALIZE_STRING(mkt_source) AS mkt_source,
  SF_NORMALIZE_STRING(landing_page) AS landing_page,
  SF_NORMALIZE_STRING(content_page) AS content_page,
  SF_NORMALIZE_STRING(campaign_context) AS campaign_context,
  SF_NORMALIZE_STRING(funnel_side) AS funnel_side,
  owner
FROM datalake_gsheets_raw.dict_taxonomy_supply
QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign, medium, source, is_branded ORDER BY id) = 1