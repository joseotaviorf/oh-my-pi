SELECT
  affiliate_type,
  lead_origin,
  lead_referring_category,
  lead_tracking_medium,
  lead_tracking_source,
  lead_type,
  mkt_channel,
  mkt_medium,
  mkt_origin,
  mkt_source,
  mkt_origin_suggestion_gsheet,
  mkt_origin_suggestion,
  is_agent_referral,
  is_branded,
  is_ops_direct_register
FROM (
  SELECT
    affiliate_type,
    lead_origin,
    lead_referring_category,
    lead_tracking_medium,
    lead_tracking_source,
    lead_type,
    mkt_channel,
    mkt_medium,
    mkt_origin,
    mkt_source,
    mkt_origin_suggestion AS mkt_origin_suggestion_gsheet,
    CASE
      WHEN affiliate_type = 'Agent'
      THEN 'Indica Aí - Agents'
      WHEN affiliate_type = 'Standard'
      THEN 'Indica Aí - General'
      WHEN COALESCE(affiliate_type, '') = '' AND lead_origin = 'PriceSuggestion'
      THEN 'Price Calculator'
      WHEN COALESCE(affiliate_type, '') = '' AND lead_origin = 'PriceSuggestionSale'
      THEN 'Price Calculator - Sale'
      WHEN COALESCE(affiliate_type, '') = ''
      AND (
        lead_type RLIKE 'OpenLink'
        OR lead_tracking_source = 'directreferral'
        OR lead_tracking_source = 'smsrf'
      )
      THEN 'DirectReferral'
      WHEN COALESCE(affiliate_type, '') = ''
      AND (
        lead_origin = 'OwnerPWA' OR lead_origin = 'Landing'
      )
      AND (
        lead_type = 'Organic' OR lead_type = 'LandingMarketing'
      )
      AND lead_tracking_source <> 'directreferral'
      THEN 'Owner PWA'
      WHEN COALESCE(affiliate_type, '') = ''
      AND (
        lead_origin = 'Inbound' OR lead_type = 'Inbound'
      )
      THEN 'Inbound'
      WHEN COALESCE(lead_type, '') = ''
      AND COALESCE(lead_origin, '') = ''
      AND affiliate_type = 'Inbound'
      AND is_ops_direct_register = 1
      THEN 'Backend'
      WHEN (
        affiliate_type RLIKE 'Doorman'
        AND (
          lead_type = 'Porteiro' OR lead_type = 'Afiliado'
        )
      )
      OR lead_type = 'Porteiro'
      THEN 'Doorman'
      ELSE 'Not Mapped'
    END AS mkt_origin_suggestion,
    CAST(is_agent_referral AS BOOLEAN) AS is_agent_referral,
    CAST(is_branded AS BOOLEAN) AS is_branded,
    CAST(is_ops_direct_register AS BOOLEAN) AS is_ops_direct_register,
    ROW_NUMBER() OVER (PARTITION BY lead_type, lead_origin, lead_tracking_medium, lead_tracking_source, affiliate_type, CAST(is_agent_referral AS BOOLEAN), lead_referring_category, CAST(is_branded AS BOOLEAN), CAST(is_ops_direct_register AS BOOLEAN) ORDER BY id) AS _w,
    id
  FROM datalake_gsheets_raw.taxonomy_growth
) AS _t
WHERE
  _w = 1