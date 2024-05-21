WITH
l2p_pre AS (
SELECT
    lf.sk_lead_date,
	dd.date,
	dd.sk_date,
	dr.city_group,
	ac.affiliate_volumetry,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	lf.mkt_medium AS supply_mkt_medium,
	lf.mkt_completion AS supply_mkt_completion,
	hp.partner AS supply_3p_partner,
	CASE WHEN hp.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3p_supply,
	rbh.partner AS supply_3pbh_partner,
	CASE WHEN rbh.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_lead AS context_origin,
	context_prospect AS context_conversion,
    CAST(DATEDIFF(DATE_TRUNC('week',TO_DATE(lf.sk_prospect_date::STRING,"yyyyMMdd")),DATE_TRUNC('week',TO_DATE(lf.sk_lead_date::STRING,"yyyyMMdd")))/7 AS INTEGER) AS quantity_weeks_conversion,
	lf.country_code,
	dhl.rental_administrator
FROM
    dw_public.dim_date dd
JOIN
    dw_datamarts.lead_listing_flows lf
        ON dd.sk_date = lf.sk_lead_date
        AND lf.sk_lead_date > 0
LEFT JOIN
    dw_public.dim_region dr
        ON dr.sk_region = lf.sk_region
LEFT JOIN
	dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = lf.sk_user_lead_affiliate
		AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
LEFT JOIN
    datalake_3p.houses_3p AS hp
        ON hp.id_house = lf.sk_house_listing / 1000
LEFT JOIN
    datalake_3p.houses_3p_bh AS rbh
        ON rbh.id_house = lf.sk_house_listing / 1000
LEFT JOIN
	dw_rent.dim_house_listing dhl
		ON lf.sk_house_listing = dhl.sk_house_listing
WHERE
    dd.date BETWEEN DATE_TRUNC('YEAR',CURRENT_DATE) - INTERVAL 4 year AND CURRENT_DATE
),
l2p AS (
SELECT
	date,
	sk_date,
	city_group,
	affiliate_volumetry,
	supply_mkt_origin,
	supply_mkt_channel,
	supply_mkt_medium,
	supply_mkt_completion,
	supply_3p_partner,
	is_3p_supply,
	supply_3pbh_partner,
	is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_origin,
	context_conversion,
	CASE
	    WHEN quantity_weeks_conversion < 0
	        THEN 'W5+'
        WHEN quantity_weeks_conversion BETWEEN 0 AND 4
            THEN 'W'||quantity_weeks_conversion
        WHEN quantity_weeks_conversion >=5
	        THEN 'W5+'
    END AS weeks_conversion,
  	COUNT(sk_lead_date) AS l2p,
	NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2opp,
	NULL::BIGINT AS opp2fl,
	NULL::BIGINT AS q2avq,
	NULL::BIGINT AS avq2opp,
	country_code,
	rental_administrator
FROM
    l2p_pre
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27, 28
),
p2q_pre AS (
SELECT
	dd.date,
	dd.sk_date,
	lf.sk_prospect_date,
	dr.city_group,
	ac.affiliate_volumetry,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	lf.mkt_medium AS supply_mkt_medium,
	lf.mkt_completion AS supply_mkt_completion,
	hp.partner AS supply_3p_partner,
	CASE WHEN hp.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3p_supply,
	rbh.partner AS supply_3pbh_partner,
	CASE WHEN rbh.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_prospect AS context_origin,
	context_qualified AS context_conversion,
    CAST(DATEDIFF(DATE_TRUNC('week',TO_DATE(lf.sk_qualified_date::STRING,"yyyyMMdd")),DATE_TRUNC('week',TO_DATE(lf.sk_prospect_date::STRING,"yyyyMMdd")))/7 AS INTEGER) AS quantity_weeks_conversion,
	lf.country_code,
	dhl.rental_administrator
FROM
    dw_public.dim_date dd
JOIN
    dw_datamarts.lead_listing_flows lf
        ON dd.sk_date = lf.sk_prospect_date
        AND lf.sk_prospect_date > 0
LEFT JOIN
    dw_public.dim_region dr
        ON dr.sk_region = lf.sk_region
LEFT JOIN
	dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = lf.sk_user_lead_affiliate
		AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
LEFT JOIN
    datalake_3p.houses_3p AS hp
        ON hp.id_house = lf.sk_house_listing / 1000
LEFT JOIN
    datalake_3p.houses_3p_bh AS rbh
        ON rbh.id_house = lf.sk_house_listing / 1000
LEFT JOIN
	dw_rent.dim_house_listing dhl
		ON lf.sk_house_listing = dhl.sk_house_listing
WHERE
    dd.date BETWEEN DATE_TRUNC('YEAR',CURRENT_DATE) - INTERVAL 4 year AND CURRENT_DATE
),
p2q AS (
SELECT
	date,
	sk_date,
	city_group,
	affiliate_volumetry,
	supply_mkt_origin,
	supply_mkt_channel,
	supply_mkt_medium,
	supply_mkt_completion,
	supply_3p_partner,
	is_3p_supply,
	supply_3pbh_partner,
	is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_origin,
	context_conversion,
	CASE
	    WHEN quantity_weeks_conversion < 0
	        THEN 'W5+'
        WHEN quantity_weeks_conversion BETWEEN 0 AND 4
            THEN 'W'||quantity_weeks_conversion
        WHEN quantity_weeks_conversion >=5
	        THEN 'W5+'
    END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	COUNT(sk_prospect_date) AS p2q, -- this count is done on the prospect date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS q2opp,
	NULL::BIGINT AS opp2fl,
	NULL::BIGINT AS q2avq,
	NULL::BIGINT AS avq2opp,
	country_code,
	rental_administrator
FROM
	p2q_pre
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27, 28
),
q2avq_pre AS (
SELECT
	dd.date,
	dd.sk_date,
	lf.sk_qualified_date,
	dr.city_group,
	ac.affiliate_volumetry,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	lf.mkt_medium AS supply_mkt_medium,
	lf.mkt_completion AS supply_mkt_completion,
	hp.partner AS supply_3p_partner,
	CASE WHEN hp.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3p_supply,
	rbh.partner AS supply_3pbh_partner,
	CASE WHEN rbh.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_qualified AS context_origin,
	context_available_qualified AS context_conversion,
    CAST(DATEDIFF(DATE_TRUNC('week',TO_DATE(lf.sk_available_qualified_date::STRING,"yyyyMMdd")),DATE_TRUNC('week',TO_DATE(lf.sk_qualified_date::STRING,"yyyyMMdd")))/7 AS INTEGER) AS quantity_weeks_conversion,
	lf.country_code,
	dhl.rental_administrator
FROM
    dw_public.dim_date dd
JOIN
    dw_datamarts.lead_listing_flows lf
        ON dd.sk_date = lf.sk_qualified_date
        AND lf.sk_qualified_date > 0
LEFT JOIN
    dw_public.dim_region dr
        ON dr.sk_region = lf.sk_region
LEFT JOIN
	dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = lf.sk_user_lead_affiliate
		AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
LEFT JOIN
    datalake_3p.houses_3p AS hp
        ON hp.id_house = lf.sk_house_listing / 1000
LEFT JOIN
    datalake_3p.houses_3p_bh AS rbh
        ON rbh.id_house = lf.sk_house_listing / 1000
LEFT JOIN
	dw_rent.dim_house_listing dhl
		ON lf.sk_house_listing = dhl.sk_house_listing
WHERE
    dd.date BETWEEN DATE_TRUNC('YEAR',CURRENT_DATE) - INTERVAL 4 year AND CURRENT_DATE
),
q2avq AS (
SELECT
	date,
	sk_date,
	city_group,
	affiliate_volumetry,
	supply_mkt_origin,
	supply_mkt_channel,
	supply_mkt_medium,
	supply_mkt_completion,
	supply_3p_partner,
	is_3p_supply,
	supply_3pbh_partner,
	is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_origin,
	context_conversion,
	CASE
	    WHEN quantity_weeks_conversion < 0
	        THEN 'W5+'
        WHEN quantity_weeks_conversion BETWEEN 0 AND 4
            THEN 'W'||quantity_weeks_conversion
        WHEN quantity_weeks_conversion >=5
	        THEN 'W5+'
    END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2opp,
	NULL::BIGINT AS opp2fl,
	COUNT(sk_qualified_date) AS q2avq, -- this count is done on the qualified date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS avq2opp,
	country_code,
	rental_administrator
FROM
	q2avq_pre
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27, 28
),
avq2opp_pre AS (
SELECT
	dd.date,
	dd.sk_date,
	lf.sk_available_qualified_date,
	dr.city_group,
	ac.affiliate_volumetry,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	lf.mkt_medium AS supply_mkt_medium,
	lf.mkt_completion AS supply_mkt_completion,
	hp.partner AS supply_3p_partner,
	CASE WHEN hp.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3p_supply,
	rbh.partner AS supply_3pbh_partner,
	CASE WHEN rbh.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_available_qualified AS context_origin,
	context_opportunity AS context_conversion,
    CAST(DATEDIFF(DATE_TRUNC('week',TO_DATE(lf.sk_opportunity_date::STRING,"yyyyMMdd")),DATE_TRUNC('week',TO_DATE(lf.sk_available_qualified_date::STRING,"yyyyMMdd")))/7 AS INTEGER) AS quantity_weeks_conversion,
	lf.country_code,
	dhl.rental_administrator
FROM
    dw_public.dim_date dd
JOIN
    dw_datamarts.lead_listing_flows lf
        ON dd.sk_date = lf.sk_available_qualified_date
        AND lf.sk_available_qualified_date > 0
LEFT JOIN
    dw_public.dim_region dr
        ON dr.sk_region = lf.sk_region
LEFT JOIN
	dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = lf.sk_user_lead_affiliate
		AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
LEFT JOIN
    datalake_3p.houses_3p AS hp
        ON hp.id_house = lf.sk_house_listing / 1000
LEFT JOIN
    datalake_3p.houses_3p_bh AS rbh
        ON rbh.id_house = lf.sk_house_listing / 1000
LEFT JOIN
	dw_rent.dim_house_listing dhl
		ON lf.sk_house_listing = dhl.sk_house_listing
WHERE
    dd.date BETWEEN DATE_TRUNC('YEAR',CURRENT_DATE) - INTERVAL 4 year AND CURRENT_DATE
),
avq2opp AS (
SELECT
	date,
	sk_date,
	city_group,
	affiliate_volumetry,
	supply_mkt_origin,
	supply_mkt_channel,
	supply_mkt_medium,
	supply_mkt_completion,
	supply_3p_partner,
	is_3p_supply,
	supply_3pbh_partner,
	is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_origin,
	context_conversion,
	CASE
	    WHEN quantity_weeks_conversion < 0
	        THEN 'W5+'
        WHEN quantity_weeks_conversion BETWEEN 0 AND 4
            THEN 'W'||quantity_weeks_conversion
        WHEN quantity_weeks_conversion >=5
	        THEN 'W5+'
    END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2opp,
	NULL::BIGINT AS opp2fl,
	NULL::BIGINT AS q2avq,
	COUNT(sk_available_qualified_date) AS avq2opp, -- this count is done on the available_qualified date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	country_code,
	rental_administrator
FROM
	avq2opp_pre
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27, 28
),
q2opp_pre AS (
SELECT
	dd.date,
	dd.sk_date,
    lf.sk_qualified_date,
	dr.city_group,
	ac.affiliate_volumetry,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	lf.mkt_medium AS supply_mkt_medium,
	lf.mkt_completion AS supply_mkt_completion,
	hp.partner AS supply_3p_partner,
	CASE WHEN hp.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3p_supply,
	rbh.partner AS supply_3pbh_partner,
	CASE WHEN rbh.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_qualified AS context_origin,
	context_opportunity AS context_conversion,
    CAST(DATEDIFF(DATE_TRUNC('week',TO_DATE(lf.sk_opportunity_date::STRING,"yyyyMMdd")),DATE_TRUNC('week',TO_DATE(lf.sk_qualified_date::STRING,"yyyyMMdd")))/7 AS INTEGER) AS quantity_weeks_conversion,
	lf.country_code,
	dhl.rental_administrator
FROM
    dw_public.dim_date dd
JOIN
    dw_datamarts.lead_listing_flows lf
        ON dd.sk_date = lf.sk_qualified_date
        AND lf.sk_qualified_date > 0
LEFT JOIN
    dw_public.dim_region dr
        ON dr.sk_region = lf.sk_region
LEFT JOIN
	dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = lf.sk_user_lead_affiliate
		AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
LEFT JOIN
    datalake_3p.houses_3p AS hp
        ON hp.id_house = lf.sk_house_listing / 1000
LEFT JOIN
    datalake_3p.houses_3p_bh AS rbh
        ON rbh.id_house = lf.sk_house_listing / 1000
LEFT JOIN
	dw_rent.dim_house_listing dhl
		ON lf.sk_house_listing = dhl.sk_house_listing
WHERE
    dd.date BETWEEN DATE_TRUNC('YEAR',CURRENT_DATE) - INTERVAL 4 year AND CURRENT_DATE -- filter data from 4 years ago

),
q2opp AS (
SELECT
	date,
	sk_date,
	city_group,
	affiliate_volumetry,
	supply_mkt_origin,
	supply_mkt_channel,
	supply_mkt_medium,
	supply_mkt_completion,
	supply_3p_partner,
	is_3p_supply,
	supply_3pbh_partner,
	is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_origin,
	context_conversion,
	CASE
	    WHEN quantity_weeks_conversion < 0
	        THEN 'W5+'
        WHEN quantity_weeks_conversion BETWEEN 0 AND 4
            THEN 'W'||quantity_weeks_conversion
        WHEN quantity_weeks_conversion >=5
	        THEN 'W5+'
    END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	NULL::BIGINT AS p2q,
	COUNT(sk_qualified_date) AS q2opp, -- this count is done on the qualified date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS opp2fl,
	NULL::BIGINT AS q2avq,
	NULL::BIGINT AS avq2opp,
	country_code,
	rental_administrator
FROM
	q2opp_pre
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27, 28
),
opp2fl_pre AS (
SELECT
	dd.date,
	dd.sk_date,
    lf.sk_house_listing,
	dr.city_group,
	ac.affiliate_volumetry,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	lf.mkt_medium AS supply_mkt_medium,
	lf.mkt_completion AS supply_mkt_completion,
	hp.partner AS supply_3p_partner,
	CASE WHEN hp.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3p_supply,
	rbh.partner AS supply_3pbh_partner,
	CASE WHEN rbh.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_opportunity AS context_origin,
	context_first_listing AS context_conversion,
    CAST(DATEDIFF(DATE_TRUNC('week',TO_DATE(lf.sk_first_listing_date::STRING,"yyyyMMdd")),DATE_TRUNC('week',TO_DATE(lf.sk_opportunity_date::STRING,"yyyyMMdd")))/7 AS INTEGER) AS quantity_weeks_conversion,
	lf.country_code,
	dhl.rental_administrator
FROM
    dw_public.dim_date dd
JOIN
    dw_datamarts.lead_listing_flows lf
        ON dd.sk_date = lf.sk_opportunity_date
        AND lf.sk_opportunity_date > 0
LEFT JOIN
    dw_public.dim_region dr
        ON dr.sk_region = lf.sk_region
LEFT JOIN
	dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = lf.sk_user_lead_affiliate
		AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
LEFT JOIN
    datalake_3p.houses_3p AS hp
        ON hp.id_house = lf.sk_house_listing / 1000
LEFT JOIN
    datalake_3p.houses_3p_bh AS rbh
        ON rbh.id_house = lf.sk_house_listing / 1000
LEFT JOIN
	dw_rent.dim_house_listing dhl
		ON lf.sk_house_listing = dhl.sk_house_listing
WHERE
    dd.date BETWEEN DATE_TRUNC('YEAR',CURRENT_DATE) - INTERVAL 4 year AND CURRENT_DATE -- filter data from 4 years ago
),
opp2fl AS (
SELECT
	date,
	sk_date,
	city_group,
	affiliate_volumetry,
	supply_mkt_origin,
	supply_mkt_channel,
	supply_mkt_medium,
	supply_mkt_completion,
	supply_3p_partner,
	is_3p_supply,
	supply_3pbh_partner,
	is_3pbh_supply,
	sales_company,
	sourcing_ops,
	origin_table,
	lead_origin,
	funnel_drop_reason,
	context_origin,
	context_conversion,
	CASE
	    WHEN quantity_weeks_conversion < 0
	        THEN 'W5+'
        WHEN quantity_weeks_conversion BETWEEN 0 AND 4
            THEN 'W'||quantity_weeks_conversion
        WHEN quantity_weeks_conversion >=5
	        THEN 'W5+'
    END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2opp,
	COUNT(DISTINCT sk_house_listing) AS opp2fl,
	NULL::BIGINT AS q2avq,
	NULL::BIGINT AS avq2opp,
	country_code,
	rental_administrator
FROM
	opp2fl_pre
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27, 28
),
union_all AS (
    SELECT * FROM l2p
	UNION ALL
	SELECT * FROM p2q
	UNION ALL
	SELECT * FROM q2opp
	UNION ALL
	SELECT * FROM opp2fl
	UNION ALL
	SELECT * FROM q2avq
	UNION ALL
	SELECT * FROM avq2opp
),
union_all_date AS (
SELECT
  dd.date,
  ua.city_group,
  ua.affiliate_volumetry,
  ua.supply_mkt_origin,
  ua.supply_mkt_channel,
  ua.supply_mkt_medium,
  ua.supply_mkt_completion,
  ua.supply_3p_partner,
  ua.is_3p_supply,
  ua.supply_3pbh_partner,
  ua.is_3pbh_supply,
  ua.sales_company,
  ua.sourcing_ops,
  ua.origin_table,
  ua.lead_origin,
  ua.funnel_drop_reason,
  ua.context_origin,
  ua.context_conversion,
  ua.weeks_conversion,
  ua.l2p,
  ua.p2q,
  ua.q2opp,
  ua.opp2fl,
  ua.q2avq,
  ua.avq2opp,
  ua.country_code,
  ua.rental_administrator
FROM
    union_all ua
RIGHT JOIN
    dw_public.dim_date dd
        ON ua.sk_date = dd.sk_date
WHERE
    dd.date BETWEEN DATE_TRUNC('YEAR',CURRENT_DATE) - INTERVAL 4 year AND CURRENT_DATE
)

SELECT
 date,
  country_code,
  city_group,
  affiliate_volumetry,
  supply_mkt_origin,
  CASE
      WHEN supply_mkt_origin = 'Owner PWA'
          THEN supply_mkt_channel
      WHEN supply_mkt_origin != 'Owner PWA'
          THEN supply_mkt_origin
  END AS supply_mkt_origin_detailed,
  supply_mkt_medium,
  CASE
      WHEN supply_mkt_origin = 'B2B' OR supply_mkt_origin = 'CIQ'
          THEN supply_mkt_origin
      WHEN supply_mkt_completion = 'Full Self-Service'
          THEN 'FSS'
      ELSE 'IS'
  END AS lead_context,
  sales_company,
  sourcing_ops,
  CASE
      WHEN sourcing_ops IN ('IS Ext', 'IS Int', 'FSS IS PhotoJob', 'Other')
          AND (supply_mkt_completion = 'Full Self-Service'
                  OR (supply_mkt_origin <> 'B2B' AND supply_mkt_origin <> 'CIQ' ))
          THEN 'IS'
      ELSE sourcing_ops
  END AS lead_processing_operation,
  origin_table,
  lead_origin,
  funnel_drop_reason,
  context_origin,
  context_conversion,
  weeks_conversion AS weeks_conversion,
  supply_3p_partner,
  supply_3pbh_partner,
  is_3p_supply,
  is_3pbh_supply,
  rental_administrator,
  SUM(COALESCE(l2p,0)) AS l2p,
  SUM(COALESCE(p2q,0)) AS p2q,
  SUM(COALESCE(q2opp,0)) AS q2opp,
  SUM(COALESCE(opp2fl,0)) AS opp2fl,
  SUM(COALESCE(q2avq,0)) AS q2avq,
  SUM(COALESCE(avq2opp,0)) AS avq2opp,
  current_timestamp AS ts_load
FROM
  union_all_date
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22
