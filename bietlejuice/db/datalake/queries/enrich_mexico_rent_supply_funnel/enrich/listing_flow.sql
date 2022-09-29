WITH listing_flows AS (
  SELECT
    lfrl.id_lead, 
    plb2b.id_house_listing,
    lfrl.id_region,
    COALESCE(lfrl.id_affiliate, lfrl.id_user_has_indicated, -1) AS id_affiliate,
    lfrl.country_code,
    COALESCE(rg.city_group, 'Not Mapped') AS city_group,
    lfrl.affiliate_type AS listing_flows_affiliate_type,
    plrl.lead_type,
    plrl.lead_origin,
    IF(lfet.id_lead IS NOT NULL, lfet.tracking_source, plrl.utm_source) AS utm_source,
    IF(lfet.id_lead IS NOT NULL, lfet.tracking_medium, plrl.utm_medium) AS utm_medium,
    CASE
      WHEN LOWER(lfet.tracking_referring_domain) LIKE '%corretor%' THEN 'Agents'
      WHEN LOWER(lfet.tracking_referring_domain) LIKE '%indicaai%' THEN 'Indica Ai'
      WHEN LOWER(lfet.tracking_referring_domain) LIKE '%proprietario%' THEN 'Owner'
      ELSE 'Other'
    END AS lead_referring_category,
    COALESCE(
      LOWER(TRIM(lfet.tracking_campaign)) RLIKE '(institucional)|(branded)'
        AND LOWER(TRIM(lfet.tracking_campaign)) NOT RLIKE '(non-branded)', plrl.is_lead_branded
    ) AS is_branded,
    (lfrl.acquisition_channel_rep = 'Inside Sales') OR (lfrl.acquisition_channel_rep = 'Admin') AS is_ops_direct_register,
    lfrl.is_b2b,
    plb2b.is_autonomous_agent,
    lfrl.is_agent_referral,
    lfrl.ts_lead,
    lfrl.ts_prospect,
    lfrl.ts_qualified,
    lfrl.ts_opportunity,
    lfrl.ts_first_listing
  FROM
    datalake_listing_flow.listing_flows_with_reprocessed_leads AS lfrl
  LEFT JOIN
    datalake_lead_tracking.lead_first_event_tracking AS lfet
      ON lfet.id_lead = lfrl.id_lead
  LEFT JOIN
    datalake_rent_potential_listing.potential_listings_reprocessed_leads AS plrl
        ON plrl.id = lfrl.id
  LEFT JOIN
    datalake_region.region AS rg
      ON rg.id = lfrl.id_region
      AND rg.country_code = 'MX'
  LEFT JOIN
    datalake_rent_potential_listing.potential_listing_b2b AS plb2b
      ON plb2b.id = lfrl.id
  WHERE
    lfrl.country_code = 'MX'
    AND DATE(lfrl.ts_lead) >= DATE('2022-06-01')
),
listing_flows_affiliates AS (
    SELECT
        lf.*,
        COALESCE(lf.listing_flows_affiliate_type,
            CASE
                WHEN ad.affiliate_type = 'Doorman' AND u.id_agent IS NOT NULL THEN 'Doorman & Agent'
                WHEN u.id_agent IS NOT NULL THEN 'Agent'
                ELSE ad.affiliate_type
            END
        ) AS affiliate_type
    FROM
      listing_flows AS lf
    LEFT JOIN
      datalake_ebdb_clean.user AS u
        ON u.id = lf.id_affiliate
    LEFT JOIN
      datalake_ebdb_clean.affiliate_data AS ad
        ON ad.id = u.id_affiliates
),
taxonomy AS (
    SELECT DISTINCT
        lead_type,
        lead_origin,
        lead_tracking_medium,
        lead_tracking_source,
        affiliate_type,
        lead_referring_category,
        CAST(is_agent_referral AS BOOLEAN) AS is_agent_referral,
        CAST(is_branded AS BOOLEAN) AS is_branded,
        CAST(is_ops_direct_register AS BOOLEAN) AS is_ops_direct_register,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source
    FROM
        datalake_gsheets_clean.taxonomy_growth
    WHERE
        COALESCE(mkt_medium, '') <> 'Doorman User'
        AND mkt_origin <> 'B2B'
),
applied_taxonomy AS (
    SELECT
        lfa.*,
        CASE
            WHEN lfa.is_b2b THEN 'B2B'
            WHEN lfa.is_autonomous_agent AND t.mkt_origin = 'Backend' THEN 'CIQ'
            WHEN lfa.affiliate_type = 'Doorman' THEN 'Doorman'
            WHEN t.mkt_origin IS NULL THEN 'Other'
            ELSE t.mkt_origin
        END AS mkt_origin,
        CASE
            WHEN lfa.is_b2b THEN NULL
            WHEN lfa.is_autonomous_agent AND t.mkt_origin = 'Backend' THEN NULL
            WHEN lfa.affiliate_type = 'Doorman' THEN 'Envio'
            WHEN t.mkt_origin IS NULL THEN 'Not Mapped'
            ELSE t.mkt_channel
        END AS mkt_channel
    FROM
      listing_flows_affiliates AS lfa
    LEFT JOIN
      taxonomy AS t
        ON COALESCE(lfa.lead_type, '') = COALESCE(t.lead_type, '')
        AND COALESCE(lfa.lead_origin, '') = COALESCE(t.lead_origin, '')
        AND COALESCE(lfa.utm_source, '') = COALESCE(t.lead_tracking_source, '')
        AND COALESCE(lfa.utm_medium, '') = COALESCE(t.lead_tracking_medium, '')
        AND COALESCE(lfa.affiliate_type, '') = COALESCE(t.affiliate_type, '')
        AND COALESCE(lfa.lead_referring_category, '') = COALESCE(t.lead_referring_category, '')
        AND COALESCE(lfa.is_branded, FALSE) = COALESCE(t.is_branded, FALSE)
        AND COALESCE(lfa.is_ops_direct_register, FALSE) = COALESCE(t.is_ops_direct_register, FALSE)
        AND COALESCE(lfa.is_agent_referral, FALSE) = COALESCE(t.is_agent_referral, FALSE)
),
mexico_channels AS (
  SELECT
    atx.id_lead,
    atx.id_house_listing,
    atx.id_region,
    atx.country_code,
    atx.city_group,
    atx.mkt_origin AS supply_mkt_origin,
    CASE 
        WHEN atx.mkt_origin = 'Owner PWA' THEN atx.mkt_channel 
        WHEN atx.mkt_origin != 'Owner PWA' THEN atx.mkt_origin 
    END AS supply_mkt_origin_detailed,
    atx.mkt_channel,
    CASE 
        WHEN (dl.unbounce_page_variant = 'Registrar Lead' OR dl.advertiser_name = 'Monkey Lab') THEN 'Human Crawlers'
        WHEN dl.unbounce_page_variant = 'Leads NAVENT' THEN 'Imuebles 24'
        WHEN dl.unbounce_page_variant = 'Landing Owner Mexico' THEN 'Landing Page - PWA'
        ELSE atx.mkt_origin
    END AS mexico_channel,
    dl.unbounce_page_variant AS ub_page_name,
    dl.advertiser_name,
    dl.source AS lead_origin,
    atx.ts_lead,
    atx.ts_prospect,
    atx.ts_qualified,
    atx.ts_opportunity,
    atx.ts_first_listing
FROM
  applied_taxonomy AS atx
LEFT JOIN
  datalake_lead.lead AS dl
    ON atx.id_lead = dl.id
WHERE
  dl.country_code = 'MX'
)
SELECT
  mc.id_lead,
  mc.id_house_listing,
  mc.id_region,
  mc.country_code,
  mc.city_group,
  mc.supply_mkt_origin,
  mc.supply_mkt_origin_detailed,
  mc.mkt_channel,
  CASE 
    WHEN mc.mexico_channel = 'CIQ' THEN 'CIB'
    WHEN mc.mexico_channel = 'Owner PWA' AND mc.supply_mkt_origin_detailed = 'Organic'  THEN 'Organic Traffic - PWA'
    WHEN mc.mexico_channel = 'Owner PWA' AND mc.supply_mkt_origin_detailed = 'Paid' THEN 'Landing Page - PWA'
    WHEN mc.mexico_channel LIKE '%Indica Aí%' THEN 'Refiere y Gana'
    ELSE mc.mexico_channel
  END AS mexico_channel,
  mc.lead_origin,
  mc.ub_page_name,
  mc.advertiser_name,
  mc.ts_lead,
  mc.ts_prospect,
  mc.ts_qualified,
  mc.ts_opportunity,
  mc.ts_first_listing
FROM
  mexico_channels AS mc