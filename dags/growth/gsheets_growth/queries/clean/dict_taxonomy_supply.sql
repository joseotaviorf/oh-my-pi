SELECT
  id,
  campaign,
  medium,
  source,
  is_branded,
  audience,
  payment_type,
  mkt_medium,
  mkt_source,
  landing_page,
  content_page,
  campaign_context,
  funnel_side,
  owner
FROM (
  SELECT
    CAST(id AS INT) AS id,
    IF(utm_campaign = '', '-1', utm_campaign) AS campaign,
    IF(utm_medium = '', '-1', utm_medium) AS medium,
    IF(utm_source = '', '-1', utm_source) AS source,
    CAST(is_branded AS BOOLEAN) AS is_branded,
    campaign_intent AS audience,
    behaviour_type AS payment_type,
    mkt_medium AS mkt_medium,
    mkt_source AS mkt_source,
    landing_page AS landing_page,
    content_page AS content_page,
    campaign_context AS campaign_context,
    funnel_side AS funnel_side,
    owner,
    ROW_NUMBER() OVER (PARTITION BY utm_campaign, utm_medium, utm_source, CAST(is_branded AS BOOLEAN) ORDER BY CAST(id AS INT)) AS _w,
    utm_campaign,
    utm_medium,
    utm_source
  FROM datalake_gsheets_raw.dict_taxonomy_supply
) AS _t
WHERE
  _w = 1