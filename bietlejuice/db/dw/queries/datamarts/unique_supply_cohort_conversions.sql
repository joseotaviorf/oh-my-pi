WITH
l2p AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	lf.mkt_completion AS supply_mkt_completion,
	sales_company,
	sourcing_ops,
	origin_table,
	context_lead AS context_origin,
	context_prospect AS context_conversion,
	CASE
	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_lead_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_prospect_date,-1)))) < 0
	        THEN 'W5+'
	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_lead_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_prospect_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(lf.sk_lead_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_prospect_date,-1))))
	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_lead_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_prospect_date,-1)))) >=5
	        THEN 'W5+'
	END AS weeks_conversion,
  	COUNT(lf.sk_lead_date) AS l2p,
	NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2opp,
	NULL::BIGINT AS opp2fl
FROM
    dim_date dd
JOIN
    datamarts.lead_listing_flows lf
        ON dd.sk_date = lf.sk_lead_date
        AND lf.sk_lead_date > 0
LEFT JOIN
    dim_region dr
        ON dr.sk_region = lf.sk_region
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
),
p2q AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	lf.mkt_completion AS supply_mkt_completion,
	sales_company,
	sourcing_ops,
	origin_table,
	context_prospect AS context_origin,
	context_qualified AS context_conversion,
	CASE
	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_qualified_date,-1)))) < 0
	        THEN 'W5+'
	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_qualified_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(lf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_qualified_date,-1))))
	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_qualified_date,-1)))) >= 5
	        THEN 'W5+'
	END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	COUNT(lf.sk_prospect_date) AS p2q, -- this count is done on the prospect date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS q2opp,
	NULL::BIGINT AS opp2fl
FROM
    dim_date dd
JOIN
    datamarts.lead_listing_flows lf
        ON dd.sk_date = lf.sk_prospect_date
        AND lf.sk_prospect_date > 0
LEFT JOIN
    dim_region dr
        ON dr.sk_region = lf.sk_region
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
),
q2opp AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	lf.mkt_completion AS supply_mkt_completion,
	sales_company,
	sourcing_ops,
	origin_table,
	context_qualified AS context_origin,
	context_opportunity AS context_conversion,
	CASE
	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_opportunity_date,-1)))) < 0
	        THEN 'W5+'
	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_opportunity_date,-1)))) BETWEEN 0 AND 4
		    THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(lf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_opportunity_date,-1))))
		WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_opportunity_date,-1)))) >= 5
		    THEN 'W5+'
	END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	NULL::BIGINT AS p2q,
	COUNT(lf.sk_qualified_date) AS q2opp, -- this count is done on the qualified date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS opp2fl
FROM
    dim_date dd
JOIN
    datamarts.lead_listing_flows lf
        ON dd.sk_date = lf.sk_qualified_date
        AND lf.sk_qualified_date > 0
LEFT JOIN
    dim_region dr
        ON dr.sk_region = lf.sk_region
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
),
opp2fl AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	lf.mkt_origin AS supply_mkt_origin,
	lf.mkt_channel AS supply_mkt_channel,
	lf.mkt_completion AS supply_mkt_completion,
	sales_company,
	sourcing_ops,
	origin_table,
	context_opportunity AS context_origin,
	context_first_listing AS context_conversion,
  	CASE
  	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_first_listing_date,-1)))) < 0
  	        THEN 'W5+'
	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_first_listing_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(lf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_first_listing_date,-1))))
	    WHEN datediff('week',DATE_TRUNC('week',DATE(lf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(lf.sk_first_listing_date,-1)))) >= 5
	        THEN 'W5+'
	END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2opp,
	COUNT(DISTINCT lf.sk_house_listing) AS opp2fl
FROM
    dim_date dd
JOIN
    datamarts.lead_listing_flows lf
        ON dd.sk_date = lf.sk_opportunity_date
        AND lf.sk_opportunity_date > 0
LEFT JOIN
    dim_region dr
        ON dr.sk_region = lf.sk_region
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
),
union_all AS (
    SELECT * FROM l2p
	UNION ALL
	SELECT * FROM p2q
	UNION ALL
	SELECT * FROM q2opp
	UNION ALL
	SELECT * FROM opp2fl
),
union_all_date AS (
SELECT
  dd."date",
  ua.city_group,
  ua.supply_mkt_origin,
  ua.supply_mkt_channel,
  ua.supply_mkt_completion,
  ua.sales_company,
  ua.sourcing_ops,
  ua.origin_table,
  ua.context_origin,
  ua.context_conversion,
  ua.weeks_conversion,
  ua.l2p,
  ua.p2q,
  ua.q2opp,
  ua.opp2fl
FROM
    union_all ua
RIGHT JOIN
    dim_date dd
        ON ua.sk_date = dd.sk_date
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE
)
SELECT
   "date",
    city_group,
    supply_mkt_origin,
    CASE
        WHEN supply_mkt_origin = 'Owner PWA'
        	THEN supply_mkt_channel
        WHEN supply_mkt_origin != 'Owner PWA'
        	THEN supply_mkt_origin
    END AS supply_mkt_origin_detailed,
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
	    WHEN sourcing_ops IN ('IS Ext', 'IS Int', 'FSS IS PhotoJob', 'Other') AND lead_context = 'FSS' THEN 'IS'
	    ELSE sourcing_ops
    END AS lead_processing_operation,
  	origin_table,
    context_origin,
  	context_conversion,
    weeks_conversion AS weeks_conversion,
    SUM(COALESCE(l2p,0)) AS l2p,
    SUM(COALESCE(p2q,0)) AS p2q,
    SUM(COALESCE(q2opp,0)) AS q2opp,
    SUM(COALESCE(opp2fl,0)) AS opp2fl,
    current_timestamp AS ts_load
FROM
    union_all_date
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12;