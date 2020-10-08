WITH
listings_rental AS (
  ----------------------------------------------------------------------------------------
  -- Supply ForRental Listings for hybrid volume measurement (listed in the same month) --
  ----------------------------------------------------------------------------------------
  SELECT DISTINCT
    dd.month_start,
    SUBSTRING(f.sk_house_listing, 1, 9) AS id_house
  FROM
    fact_house_listing_flows AS f
      JOIN dim_date AS dd
        ON f.sk_first_listing_date = dd.sk_date
    WHERE
      f.sk_first_listing_date >= 20200101
      AND f.sk_house_listing > 0
),
costs_targets_results_combined AS (
  ---------------------------------
  -- Supply ForSale Leads Volume --
  ---------------------------------
  SELECT
    f.sk_lead_date as sk_date,
    COALESCE(dr.city_group, 'Not Mapped') AS city_group,
    f.mkt_origin,
    f.mkt_channel,
    f.mkt_medium,
    f.mkt_source,
    dl.utm_campaign,
    dl.utm_content,
    dl.utm_term,
	  CASE
	      WHEN LOWER(dl.utm_campaign) ~ '(sale|girafa|vender)' OR f.sk_user_lead_affiliate in (912255, 360754, 1711931, 2257503)
	          THEN 'Sale'
	      WHEN f.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(dl.utm_campaign) LIKE '%hybrid%'
	          THEN 'Hybrid'
        WHEN ((dl.utm_campaign IS NULL OR dl.utm_campaign = '') AND LOWER(f.mkt_channel) NOT LIKE '%paid%') OR (LOWER(dl.utm_campaign) LIKE '%branded%' AND LOWER(dl.utm_campaign) NOT LIKE '%non-branded%')
	          THEN 'Organic'
	     ELSE 'Rental'
	  END AS campaign_context,
    COUNT(DISTINCT CASE WHEN sk_lead_date > 0 THEN f.sk_house_listing_flow ELSE NULL END) AS leads,
    COUNT(NULL) AS prospects,
    COUNT(NULL) AS qualifieds,
    COUNT(NULL) AS opportunities,
    COUNT(NULL) AS first_listings,
    COUNT(NULL) AS hybrid_listings,
    SUM(0::FLOAT) AS cost,
    SUM(0::FLOAT) AS prospects_target,
    SUM(0::FLOAT) AS qualifieds_target,
    SUM(0::FLOAT) AS opportunities_target,
    SUM(0::FLOAT) AS first_listings_target,
    SUM(0::FLOAT) AS budget
  FROM
    sale.fact_listing_flows AS f
    JOIN dim_lead AS dl
      ON dl.sk_lead = f.sk_lead
    JOIN dim_region AS dr
      ON f.sk_region = dr.sk_region
  WHERE
    f.sk_lead_date > 0
  GROUP BY 1,2,3,4,5,6,7,8,9,10

  UNION ALL

  -------------------------------------
  -- Supply ForSale Prospects Volume --
  -------------------------------------
  SELECT
    f.sk_prospect_date as sk_date,
    COALESCE(dr.city_group, 'Not Mapped') AS city_group,
    f.mkt_origin,
    f.mkt_channel,
    f.mkt_medium,
    f.mkt_source,
    dl.utm_campaign,
    dl.utm_content,
    dl.utm_term,
	  CASE
	      WHEN LOWER(dl.utm_campaign) ~ '(sale|girafa|vender)' OR f.sk_user_lead_affiliate in (912255, 360754, 1711931, 2257503)
	          THEN 'Sale'
	      WHEN f.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(dl.utm_campaign) LIKE '%hybrid%'
	          THEN 'Hybrid'
        WHEN ((dl.utm_campaign IS NULL OR dl.utm_campaign = '') AND LOWER(f.mkt_channel) NOT LIKE '%paid%') OR (LOWER(dl.utm_campaign) LIKE '%branded%' AND LOWER(dl.utm_campaign) NOT LIKE '%non-branded%')
	          THEN 'Organic'
	     ELSE 'Rental'
	  END AS campaign_context,
    COUNT(NULL) AS leads,
    COUNT(DISTINCT CASE WHEN sk_prospect_date > 0 THEN f.sk_house_listing_flow ELSE NULL END) AS prospects,
    COUNT(NULL) AS qualifieds,
    COUNT(NULL) AS opportunities,
    COUNT(NULL) AS first_listings,
    COUNT(NULL) AS hybrid_listings,
    SUM(0::FLOAT) AS cost,
    SUM(0::FLOAT) AS prospects_target,
    SUM(0::FLOAT) AS qualifieds_target,
    SUM(0::FLOAT) AS opportunities_target,
    SUM(0::FLOAT) AS first_listings_target,
    SUM(0::FLOAT) AS budget
  FROM
    sale.fact_listing_flows AS f
    JOIN dim_lead AS dl
      ON dl.sk_lead = f.sk_lead
    JOIN dim_region AS dr
      ON f.sk_region = dr.sk_region
  WHERE
    f.sk_prospect_date > 0
  GROUP BY 1,2,3,4,5,6,7,8,9,10

  UNION ALL

  --------------------------------------
  -- Supply ForSale Qualifieds Volume --
  --------------------------------------
  SELECT
    sk_qualified_date as sk_date,
    COALESCE(dr.city_group, 'Not Mapped') AS city_group,
    f.mkt_origin,
    f.mkt_channel,
    f.mkt_medium,
    f.mkt_source,
    dl.utm_campaign,
    dl.utm_content,
    dl.utm_term,
	  CASE
	      WHEN LOWER(dl.utm_campaign) ~ '(sale|girafa|vender)' OR f.sk_user_lead_affiliate in (912255, 360754, 1711931, 2257503)
	          THEN 'Sale'
	      WHEN f.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(dl.utm_campaign) LIKE '%hybrid%'
	          THEN 'Hybrid'
        WHEN ((dl.utm_campaign IS NULL OR dl.utm_campaign = '') AND LOWER(f.mkt_channel) NOT LIKE '%paid%') OR (LOWER(dl.utm_campaign) LIKE '%branded%' AND LOWER(dl.utm_campaign) NOT LIKE '%non-branded%')
	          THEN 'Organic'
	     ELSE 'Rental'
	  END AS campaign_context,
    COUNT(NULL) AS leads,
    COUNT(NULL) AS prospects,
    COUNT(DISTINCT CASE WHEN sk_qualified_date > 0 THEN f.sk_house_listing_flow ELSE NULL END) AS qualifieds,
    COUNT(NULL) AS opportunities,
    COUNT(NULL) AS first_listings,
    COUNT(NULL) AS hybrid_listings,
    SUM(0::FLOAT) AS cost,
    SUM(0::FLOAT) AS prospects_target,
    SUM(0::FLOAT) AS qualifieds_target,
    SUM(0::FLOAT) AS opportunities_target,
    SUM(0::FLOAT) AS first_listings_target,
    SUM(0::FLOAT) AS budget
  FROM
    sale.fact_listing_flows AS f
    JOIN dim_lead AS dl
      ON dl.sk_lead = f.sk_lead
    JOIN dim_region AS dr
      ON f.sk_region = dr.sk_region
  WHERE
    f.sk_qualified_date > 0
  GROUP BY 1,2,3,4,5,6,7,8,9,10

  UNION ALL

  -----------------------------------------
  -- Supply ForSale Opportunities Volume --
  -----------------------------------------
  SELECT
    sk_opportunity_date as sk_date,
    COALESCE(dr.city_group, 'Not Mapped') AS city_group,
    f.mkt_origin,
    f.mkt_channel,
    f.mkt_medium,
    f.mkt_source,
    dl.utm_campaign,
    dl.utm_content,
    dl.utm_term,
	  CASE
	      WHEN LOWER(dl.utm_campaign) ~ '(sale|girafa|vender)' OR f.sk_user_lead_affiliate in (912255, 360754, 1711931, 2257503)
	          THEN 'Sale'
	      WHEN f.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(dl.utm_campaign) LIKE '%hybrid%'
	          THEN 'Hybrid'
        WHEN ((dl.utm_campaign IS NULL OR dl.utm_campaign = '') AND LOWER(f.mkt_channel) NOT LIKE '%paid%') OR (LOWER(dl.utm_campaign) LIKE '%branded%' AND LOWER(dl.utm_campaign) NOT LIKE '%non-branded%')
	          THEN 'Organic'
	     ELSE 'Rental'
	  END AS campaign_context,
    COUNT(NULL) AS leads,
    COUNT(NULL) AS prospects,
    COUNT(NULL) AS qualifieds,
    COUNT(DISTINCT CASE WHEN sk_opportunity_date > 0 THEN f.sk_house_listing_flow ELSE NULL END) AS opportunities,
    COUNT(NULL) AS first_listings,
    COUNT(NULL) AS hybrid_listings,
    SUM(0::FLOAT) AS cost,
    SUM(0::FLOAT) AS prospects_target,
    SUM(0::FLOAT) AS qualifieds_target,
    SUM(0::FLOAT) AS opportunities_target,
    SUM(0::FLOAT) AS first_listings_target,
    SUM(0::FLOAT) AS budget
  FROM
    sale.fact_listing_flows AS f
    JOIN dim_lead AS dl
      ON dl.sk_lead = f.sk_lead
    JOIN dim_region AS dr
      ON f.sk_region = dr.sk_region
  WHERE
    f.sk_opportunity_date > 0
  GROUP BY 1,2,3,4,5,6,7,8,9,10

  UNION ALL

  ------------------------------------------
  -- Supply ForSale First Listings Volume --
  ------------------------------------------
  SELECT
    sk_date,
    COALESCE(dr.city_group, 'Not Mapped') AS city_group,
    f.mkt_origin,
    f.mkt_channel,
    f.mkt_medium,
    f.mkt_source,
    dl.utm_campaign,
    dl.utm_content,
    dl.utm_term,
	  CASE
	      WHEN LOWER(dl.utm_campaign) ~ '(sale|girafa|vender)' OR f.sk_user_lead_affiliate in (912255, 360754, 1711931, 2257503)
	          THEN 'Sale'
	      WHEN f.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(dl.utm_campaign) LIKE '%hybrid%'
	          THEN 'Hybrid'
        WHEN ((dl.utm_campaign IS NULL OR dl.utm_campaign = '') AND LOWER(f.mkt_channel) NOT LIKE '%paid%') OR (LOWER(dl.utm_campaign) LIKE '%branded%' AND LOWER(dl.utm_campaign) NOT LIKE '%non-branded%')
	          THEN 'Organic'
	     ELSE 'Rental'
	  END AS campaign_context,
    COUNT(NULL) AS leads,
    COUNT(NULL) AS prospects,
    COUNT(NULL) AS qualifieds,
    COUNT(NULL) AS opportunities,
    COUNT(DISTINCT CASE WHEN f.sk_first_listing_date > 0 THEN f.sk_house_listing_flow ELSE NULL END) AS first_listings,
    COUNT(DISTINCT CASE WHEN lr.id_house IS NOT NULL THEN f.sk_house_listing_flow ELSE NULL END) AS hybrid_listings,
    SUM(0::FLOAT) AS cost,
    SUM(0::FLOAT) AS prospects_target,
    SUM(0::FLOAT) AS qualifieds_target,
    SUM(0::FLOAT) AS opportunities_target,
    SUM(0::FLOAT) AS first_listings_target,
    SUM(0::FLOAT) AS budget
  FROM
    sale.fact_listing_flows AS f
    JOIN dim_lead AS dl
      ON dl.sk_lead = f.sk_lead
    JOIN dim_region AS dr
      ON f.sk_region = dr.sk_region
    JOIN dim_date AS dd
      ON f.sk_first_listing_date = dd.sk_date
    LEFT JOIN listings_rental AS lr
      ON SUBSTRING(f.sk_house_listing, 1, 9) = lr.id_house
      AND dd.month_start = lr.month_start
  WHERE
    f.sk_first_listing_date > 0
  GROUP BY 1,2,3,4,5,6,7,8,9,10

  UNION ALL

  -----------------------------------------
  -- Supply ForSale Marketing Investment --
  -----------------------------------------
  SELECT
    NULLIF(mkt.sk_date, -1) AS sk_date,
    COALESCE(mkt.city_group, 'Not Mapped') AS city_group,
    REPLACE(mkt.mkt_origin, ' - Sale', '') AS mkt_origin,
    mkt.mkt_channel,
    mkt.mkt_medium,
    mkt.mkt_source,
    mkt.utm_campaign,
    mkt.utm_content,
    mkt.utm_term,
	  CASE
	      WHEN LOWER(mkt.utm_campaign) ~ '(sale|girafa|vender)'
	          THEN 'Sale'
	      WHEN mkt.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(mkt.utm_campaign) LIKE '%hybrid%'
	          THEN 'Hybrid'
	    WHEN ((mkt.utm_campaign IS NULL OR mkt.utm_campaign = '') AND LOWER(mkt.mkt_channel) NOT LIKE '%paid%') OR (LOWER(mkt.utm_campaign) LIKE '%branded%' and LOWER(mkt.utm_campaign) NOT LIKE '%non-branded%')
	          THEN 'Organic'
	     ELSE 'Rental'
	  END AS campaign_context,
    COUNT(NULL) AS leads,
    COUNT(NULL) AS prospects,
    COUNT(NULL) AS qualifieds,
    COUNT(NULL) AS opportunities,
    COUNT(NULL) AS first_listings,
    COUNT(NULL) AS hybrid_listings,
    SUM(COALESCE(mkt.cost, 0)) AS cost,
    SUM(0::FLOAT) AS prospects_target,
    SUM(0::FLOAT) AS qualifieds_target,
    SUM(0::FLOAT) AS opportunities_target,
    SUM(0::FLOAT) AS first_listings_target,
    SUM(0::FLOAT) AS budget
  FROM
    marketing.fact_marketing_daily_costs mkt
  WHERE
      mkt.mkt_origin IN ('Price Calculator - Sale', 'Owner PWA - Sale')
  GROUP BY 1,2,3,4,5,6,7,8,9,10

  UNION ALL

  -----------------------------------
  -- Supply ForSale Funnel Targets --
  -----------------------------------
  SELECT
    TO_CHAR(DATE(NULLIF(str.date, '')), 'YYYYMMDD')::INT AS sk_date,
    COALESCE(NULLIF(str.city_group, ''),'Not Mapped')::TEXT AS city_group,
    NULLIF(str.mkt_origin, '')::TEXT as mkt_origin,
    CASE str.mkt_origin
      WHEN 'Owner PWA'
        THEN NULLIF(str.mkt_channel, '')::TEXT
      ELSE NULL::TEXT
    END AS mkt_channel,
    NULL::TEXT AS mkt_medium,
    NULL::TEXT AS mkt_source,
    NULL::TEXT AS utm_campaign,
    NULL::TEXT AS utm_content,
    NULL::TEXT AS utm_term,
    NULL::TEXT AS campaign_context,
    COUNT(NULL) AS leads,
    COUNT(NULL) AS prospects,
    COUNT(NULL) AS qualifieds,
    COUNT(NULL) AS opportunities,
    COUNT(NULL) AS first_listings,
    COUNT(NULL) AS hybrid_listings,
    SUM(0::FLOAT) AS cost,
    SUM(NULLIF(prospects, '')::FLOAT) AS prospects_target,
    SUM(NULLIF(qualifieds, '')::FLOAT) AS qualifieds_target,
    SUM(NULLIF(opportunities, '')::FLOAT) AS opportunities_target,
    SUM(NULLIF(first_listings, '')::FLOAT) AS first_listings_target,
    SUM(0::FLOAT) AS budget
  FROM
    datalake_raw.gsheets_sale_supply_targets AS str
  WHERE
    mkt_origin != 'All'
  GROUP BY 1,2,3,4,5,6,7,8,9,10

  UNION ALL

  ---------------------------------
  -- Supply ForSale Cost Targets --
  ---------------------------------
  SELECT
    TO_CHAR(DATE(NULLIF(ct.date, '')), 'YYYYMMDD')::INT AS sk_date,
    COALESCE(NULLIF(ct.city_group, ''),'Not Mapped')::TEXT AS city_group,
    CASE
      WHEN ct.planning_mkt_level3 = 'PWA - Paid'
        THEN 'Owner PWA'
      ELSE ct.planning_mkt_level3
    END AS mkt_origin,
    NULL::TEXT AS mkt_channel,
    NULL::TEXT AS mkt_medium,
    NULL::TEXT AS mkt_source,
    NULL::TEXT AS utm_campaign,
    NULL::TEXT AS utm_content,
    NULL::TEXT AS utm_term,
    NULL::TEXT AS campaign_context,
    COUNT(NULL) AS leads,
    COUNT(NULL) AS prospects,
    COUNT(NULL) AS qualifieds,
    COUNT(NULL) AS opportunities,
    COUNT(NULL) AS first_listings,
    COUNT(NULL) AS hybrid_listings,
    SUM(0::FLOAT) AS cost,
    SUM(0::FLOAT) AS prospects_target,
    SUM(0::FLOAT) AS qualifieds_target,
    SUM(0::FLOAT) AS opportunities_target,
    SUM(0::FLOAT) AS first_listings_target,
    SUM(NULLIF(ct.cost_target, '')::FLOAT) AS budget
  FROM datalake_raw.gsheets_costs_targets AS ct
  WHERE
    business = 'Sales'
    AND planning_mkt_level1 = 'Supply'
    AND planning_mkt_level2 = 'Landlords'
  GROUP BY 1,2,3,4,5,6,7,8,9,10
)
SELECT
  date,
  city_group,
  mkt_origin,
  mkt_channel,
  mkt_medium,
  mkt_source,
  utm_campaign,
  utm_content,
  utm_term,
  campaign_context,
  SUM(leads) AS leads,
  SUM(prospects) AS prospects,
  SUM(qualifieds) AS qualifieds,
  SUM(opportunities) AS opportunities,
  SUM(first_listings) AS first_listings,
  SUM(hybrid_listings) AS hybrid_listings,
  SUM(cost) AS cost,
  SUM(prospects_target) AS prospects_target,
  SUM(qualifieds_target) AS qualifieds_target,
  SUM(opportunities_target) AS opportunities_target,
  SUM(first_listings_target) AS first_listings_target,
  SUM(budget) AS budget
FROM costs_targets_results_combined
  JOIN dim_date AS dd
    USING(sk_date)
GROUP BY 1,2,3,4,5,6,7,8,9,10