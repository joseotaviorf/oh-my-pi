WITH
lead_ AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	sourcing_ops,
	context_lead AS context,
  	COUNT(lf.sk_lead_date) AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings
FROM dim_date dd
JOIN datamarts.lead_listing_flows lf
  ON dd.sk_date = lf.sk_lead_date
  AND lf.sk_lead_date > 0
LEFT JOIN dim_region dr
  ON dr.sk_region = lf.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7
),
prospect AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	sourcing_ops,
	context_prospect AS context,
	NULL::BIGINT AS leads,
	COUNT(lf.sk_prospect_date) AS prospects, -- this count is done on the prospect date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings
FROM dim_date dd
JOIN datamarts.lead_listing_flows lf
  ON dd.sk_date = lf.sk_prospect_date
  AND lf.sk_prospect_date > 0
LEFT JOIN dim_region dr
  ON dr.sk_region = lf.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7
),
qualified AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	sourcing_ops,
	context_qualified AS context,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	COUNT(lf.sk_qualified_date) AS qualifieds, -- this count is done on the qualified date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings
FROM dim_date dd
JOIN datamarts.lead_listing_flows lf
  ON dd.sk_date = lf.sk_qualified_date
  AND lf.sk_qualified_date > 0
LEFT JOIN dim_region dr
  ON dr.sk_region = lf.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7
),
opportunity AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	sourcing_ops,
	context_opportunity AS context,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	COUNT(DISTINCT lf.sk_house_listing) AS opportunities,
	NULL::BIGINT AS first_listings
FROM dim_date dd
JOIN datamarts.lead_listing_flows lf
  ON dd.sk_date = lf.sk_opportunity_date
  AND lf.sk_opportunity_date > 0
LEFT JOIN dim_region dr
  ON dr.sk_region = lf.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7
),
listing AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	sourcing_ops,
	context_first_listing AS context,
  	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	COUNT(lf.sk_first_listing_date) AS first_listings
FROM dim_date dd
JOIN datamarts.lead_listing_flows lf
  ON dd.sk_date = lf.sk_first_listing_date
  AND lf.sk_first_listing_date > 0
LEFT JOIN dim_region dr
  ON dr.sk_region = lf.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7
),
union_all AS (
  SELECT * FROM lead_
	UNION ALL
	SELECT * FROM prospect
	UNION ALL
	SELECT * FROM qualified
	UNION ALL
	SELECT * FROM opportunity
	UNION ALL
	SELECT * FROM listing
),
union_all_date AS (
SELECT
  dd."date",
  ua.city_group,
  ua.supply_mkt_origin,
  ua.supply_mkt_channel,
  ua.sourcing_ops,
  ua.context,
  ua.leads,
  ua.prospects,
  ua.qualifieds,
  ua.opportunities,
  ua.first_listings
FROM union_all ua
RIGHT JOIN dim_date dd
  ON ua.sk_date = dd.sk_date
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE
)
SELECT
	"date",
	city_group,
	supply_mkt_origin,
  	CASE WHEN supply_mkt_origin = 'Owner PWA' THEN supply_mkt_channel
  	   when supply_mkt_origin != 'Owner PWA' THEN supply_mkt_origin
  	   END AS supply_mkt_origin_detailed,
  	sourcing_ops,
  	context,
    SUM(COALESCE(leads,0)) AS leads,
    SUM(COALESCE(prospects,0)) AS prospects,
    SUM(COALESCE(qualifieds,0)) AS qualifieds,
    SUM(COALESCE(opportunities,0)) AS opportunities,
    SUM(COALESCE(first_listings,0)) AS first_listings,
    current_timestamp AS ts_load
FROM union_all
GROUP BY "date", city_group, 3, 4, 5, 6;