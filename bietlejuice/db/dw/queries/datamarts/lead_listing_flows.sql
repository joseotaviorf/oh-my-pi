WITH
source_ops_rent AS (
	WITH
	photo_job AS (
	    SELECT
	        fpj.sk_house_listing,
	        MIN(fpj.sk_date_job_created) AS sk_first_photo_job_date,
	        SUM(CASE WHEN creation_origin IN ('InsideSales_internal','InsideSales_external') THEN 1 ELSE 0 END) AS photo_job_by_isales
	    FROM fact_photo_job fpj
	    GROUP BY 1
	)
	SELECT
	    hlf.sk_house_listing_flow,
	    hlf.sk_lead,
	    hlf.sk_house_listing,
	    case
	        WHEN hlf.mkt_origin = 'B2B' AND hlf.is_b2b = TRUE
	            THEN 'B2B'
	        WHEN (hlf.mkt_completion = 'Full Self-Service' OR (hlf.has_isales_intervention = false)) AND (photo_job_by_isales < 1)
	            THEN 'FSS'
	        WHEN (hlf.mkt_completion = 'Full Self-Service' OR (hlf.has_isales_intervention = false)) AND photo_job_by_isales >= 1 AND sk_first_photo_job_date = hlf.sk_opportunity_date
	            THEN 'FSS IS PhotoJob'
	        WHEN coalesce(du.sales_company,dl.sales_company) IN ('QUINTO_ANDAR','')
	            THEN 'IS Int'
	        WHEN coalesce(du.sales_company,dl.sales_company) IN ('ACTION_LINE','ATENTO','ALGAR')
	            THEN 'IS Ext'
	        ELSE  'Other'
	    END  AS sourcing_ops,
	     CASE WHEN hlf.sk_lead_date = ssf.sk_lead_date AND hlf.sk_lead_date > 0 THEN 'Hybrid'
	            WHEN hlf.sk_lead_date > 0 THEN 'Rent'
	            ELSE NULL END AS lead_context,
	        CASE WHEN hlf.sk_prospect_date = ssf.sk_prospect_date AND hlf.sk_prospect_date > 0 THEN 'Hybrid'
	            WHEN hlf.sk_prospect_date > 0 THEN 'Rent'
	            ELSE NULL END AS prospect_context,
	        CASE WHEN hlf.sk_qualified_date = ssf.sk_qualified_date AND hlf.sk_qualified_date > 0 THEN 'Hybrid'
	            WHEN hlf.sk_qualified_date > 0  THEN 'Rent'
	            ELSE NULL END AS qualified_context,
	        CASE WHEN hlf.sk_opportunity_date = ssf.sk_opportunity_date AND hlf.sk_opportunity_date > 0 THEN 'Hybrid'
	            WHEN hlf.sk_opportunity_date > 0  THEN 'Rent'
	            ELSE NULL END AS opportunity_context,
	        CASE WHEN hlf.sk_first_listing_date = ssf.sk_first_listing_date AND hlf.sk_first_listing_date > 0 THEN 'Hybrid'
	            WHEN hlf.sk_first_listing_date > 0  THEN 'Rent'
	            ELSE NULL END AS first_listing_context,
	        COALESCE(du.sales_company, dl.sales_company) AS sales_company
	FROM fact_house_listing_flows hlf
	    JOIN dim_lead dl
	        ON dl.sk_lead = hlf.sk_lead
	    LEFT JOIN quintoandar.dim_user_sales_rep du
	        ON du.sk_user_sales_rep = hlf.sk_user_house_registrant
	    LEFT JOIN photo_job pj
	        ON pj.sk_house_listing = hlf.sk_house_listing
	    LEFT JOIN  sale.fact_listing_flows ssf
	        ON hlf.sk_house_listing_flow = ssf.sk_house_listing_flow
),
source_ops_sale AS (
	with
	photo_job AS (
	    SELECT
	        fpj.sk_house_listing,
	        MIN(fpj.sk_date_job_created) AS sk_first_photo_job_date,
	        SUM(CASE WHEN creation_origin IN ('InsideSales_internal','InsideSales_external') THEN 1 ELSE 0 END) AS photo_job_by_isales
	    FROM fact_photo_job fpj
	    GROUP BY 1
	)
	SELECT
	    ssf.sk_house_listing_flow,
	    ssf.sk_lead,
	    ssf.sk_house_listing,
	    case
	        WHEN ssf.mkt_origin = 'B2B' AND ssf.is_b2b = TRUE
	            THEN 'B2B'
	        WHEN (ssf.mkt_completion = 'Full Self-Service' OR (ssf.has_isales_intervention = false)) AND (photo_job_by_isales < 1)
	            THEN 'FSS'
	        WHEN (ssf.mkt_completion = 'Full Self-Service' OR (ssf.has_isales_intervention = false)) AND photo_job_by_isales >= 1 AND sk_first_photo_job_date = ssf.sk_opportunity_date
	            THEN 'FSS IS PhotoJob'
	        WHEN coalesce(du.sales_company,dl.sales_company) IN ('QUINTO_ANDAR','')
	            THEN 'IS Int'
	        WHEN coalesce(du.sales_company,dl.sales_company) IN ('ACTION_LINE','ATENTO','ALGAR')
	            THEN 'IS Ext'
	        ELSE  'Other'
	    END AS sourcing_ops,
	        CASE WHEN hlf.sk_lead_date = ssf.sk_lead_date AND ssf.sk_lead_date > 0 THEN 'Hybrid'
	            WHEN ssf.sk_lead_date > 0 THEN 'Sale'
	            ELSE NULL END AS lead_context,
	        CASE WHEN hlf.sk_prospect_date = ssf.sk_prospect_date AND ssf.sk_prospect_date > 0 THEN 'Hybrid'
	            WHEN ssf.sk_prospect_date > 0 THEN 'Sale'
	            ELSE NULL END AS prospect_context,
	        CASE WHEN hlf.sk_qualified_date = ssf.sk_qualified_date AND ssf.sk_qualified_date > 0 THEN 'Hybrid'
	            WHEN ssf.sk_qualified_date > 0  THEN 'Sale'
	            ELSE NULL END AS qualified_context,
	        CASE WHEN hlf.sk_opportunity_date = ssf.sk_opportunity_date AND ssf.sk_opportunity_date > 0 THEN 'Hybrid'
	            WHEN ssf.sk_opportunity_date > 0  THEN 'Sale'
	            ELSE NULL END AS opportunity_context,
	        CASE WHEN hlf.sk_first_listing_date = ssf.sk_first_listing_date AND ssf.sk_first_listing_date > 0 THEN 'Hybrid'
	            WHEN ssf.sk_first_listing_date > 0  THEN 'Sale'
	            ELSE NULL END AS first_listing_context,
	        COALESCE(du.sales_company, dl.sales_company) AS sales_company
	FROM sale.fact_listing_flows ssf
	    JOIN dim_lead dl
	        ON dl.sk_lead = ssf.sk_lead
	    LEFT JOIN quintoandar.dim_user_sales_rep du
	        ON du.sk_user_sales_rep = ssf.sk_user_house_registrant
	    LEFT JOIN photo_job pj
	        ON pj.sk_house_listing = ssf.sk_house_listing
	    LEFT JOIN fact_house_listing_flows hlf
	        ON hlf.sk_house_listing_flow = ssf.sk_house_listing_flow
),
fact_sale AS (
	SELECT
	    ssf.sk_house_listing_flow,
	    ssf.sk_lead,
		ssf.sk_house_listing,
		ssf.sk_region,
		ssf.sk_lead_date,
	    ssf.sk_prospect_date,
	    ssf.sk_qualified_date,
	    ssf.sk_opportunity_date,
	    ssf.sk_first_listing_date,
	   	sor.lead_context AS context_lead,
	    sor.prospect_context AS context_prospect,
	    sor.qualified_context AS context_qualified,
	    sor.opportunity_context AS context_opportunity,
	    sor.first_listing_context AS context_first_listing,
	    ssf.mkt_origin,
	    ssf.mkt_completion,
	    ssf.mkt_channel,
	    sor.sales_company,
	    sor.sourcing_ops,
	    'Sale' AS origin_table
	FROM sale.fact_listing_flows ssf
	JOIN source_ops_sale AS sor
	  ON sor.sk_house_listing_flow = ssf.sk_house_listing_flow
),
fact_rent AS (
	SELECT
	    hlf.sk_house_listing_flow,
	    hlf.sk_lead,
		hlf.sk_house_listing,
		hlf.sk_region,
		hlf.sk_lead_date,
	    hlf.sk_prospect_date,
	    hlf.sk_qualified_date,
	    hlf.sk_opportunity_date,
	    hlf.sk_first_listing_date,
	    sor.lead_context AS context_lead,
	    sor.prospect_context AS context_prospect,
	    sor.qualified_context AS context_qualified,
	    sor.opportunity_context AS context_opportunity,
	    sor.first_listing_context AS context_first_listing,
	    hlf.mkt_origin,
	    hlf.mkt_completion,
	    hlf.mkt_channel,
	    sor.sales_company,
	    sor.sourcing_ops,
	    'Rent' AS origin_table
	FROM fact_house_listing_flows hlf
	JOIN source_ops_rent AS sor
	  ON sor.sk_house_listing_flow = hlf.sk_house_listing_flow
)
SELECT *
FROM fact_rent
	UNION ALL
	SELECT *
	FROM fact_sale;
