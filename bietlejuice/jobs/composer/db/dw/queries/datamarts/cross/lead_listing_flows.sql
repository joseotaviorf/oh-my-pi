WITH
fact_house_listing_flows_adjust AS (
SELECT
    hl.sk_house_listing_flow,
    hl.sk_lead,
    hl.sk_house_listing,
    hl.sk_region,
    hl.mkt_completion,
    hl.has_isales_intervention,
    hl.sk_lead_date,
    hl.sk_prospect_date,
    hl.sk_qualified_date,
    hl.sk_opportunity_date,
    hl.sk_first_listing_date,
    hl.sk_first_contact_date,
    hl.sk_conversion_date,
    hl.sk_discard_date,
    hl.lead_origin,
	hl.funnel_drop_reason,
	hl.mkt_channel,
	hl.mkt_source,
	hl.mkt_medium,
	hl.lead_context_origin,
	hl.sk_user_lead_affiliate,
	hl.sk_user_house_registrant,
	hl.is_b2b,
    CASE
        WHEN ciq.businesscontext= 'RENT' AND ciq.type_big_agent = 'CIQ_FULL'
            THEN 'CIQ'
        WHEN hl.mkt_origin = 'CIQ' AND ciq.businesscontext= 'RENT' AND ciq.type_big_agent = 'CIQ_MANAGER'
            THEN 'Backend'
        WHEN hl.mkt_origin = 'CIQ' AND ciq.type_big_agent IS NULL
            THEN 'Other'
        ELSE hl.mkt_origin
    END AS mkt_origin
FROM fact_house_listing_flows hl
LEFT JOIN datamarts.quintoandar_consultant_listings ciq
	        ON ciq.sk_house_listing = hl.sk_house_listing AND ciq.businesscontext= 'RENT'
),
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
	        WHEN hlf.mkt_origin = 'CIQ'
	        	THEN 'CIQ'
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
	        COALESCE(du.sales_company, dl.sales_company) AS sales_company,
	        hlf.lead_origin,
	        hlf.funnel_drop_reason,
	        sk_first_photo_job_date
	FROM fact_house_listing_flows_adjust hlf
	    JOIN dim_lead dl
	        ON dl.sk_lead = hlf.sk_lead
	    LEFT JOIN quintoandar.dim_user_sales_rep du
	        ON du.sk_user_sales_rep = hlf.sk_user_house_registrant
	    LEFT JOIN photo_job pj
	        ON pj.sk_house_listing = hlf.sk_house_listing
	    LEFT JOIN  sale.fact_listing_flows ssf
	        ON hlf.sk_house_listing_flow = ssf.sk_house_listing_flow
),
sale_fact_listing_flows_adjust AS (
SELECT
    hl.sk_house_listing_flow,
    hl.sk_lead,
    hl.sk_house_listing,
    hl.sk_region,
    hl.mkt_completion,
    hl.has_isales_intervention,
    hl.sk_lead_date,
    hl.sk_prospect_date,
    hl.sk_qualified_date,
    hl.sk_opportunity_date,
    hl.sk_first_listing_date,
    hl.sk_first_contact_date,
    hl.sk_conversion_date,
    hl.sk_discard_date,
    hl.lead_origin,
	hl.funnel_drop_reason,
	hl.mkt_channel,
	hl.mkt_source,
	hl.mkt_medium,
	hl.lead_context_origin,
	hl.sk_user_lead_affiliate,
	hl.sk_user_house_registrant,
	hl.is_b2b,
    CASE
        WHEN  ciq.type_big_agent = 'CIQ_FULL' OR (type_big_agent='CIQ_MANAGER' AND dt_sale > dt_ciq_started)
            THEN 'CIQ'
        ELSE hl.mkt_origin
    END AS mkt_origin
FROM sale.fact_listing_flows hl
LEFT JOIN datamarts.quintoandar_consultant_listings ciq
	        ON LEFT(ciq.sk_house_listing,9) = LEFT(hl.sk_house_listing,9) AND ciq.businesscontext='SALE'
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
	        WHEN ssf.mkt_origin = 'CIQ'
	        	THEN 'CIQ'
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
	        COALESCE(du.sales_company, dl.sales_company) AS sales_company,
	        ssf.lead_origin,
	        ssf.funnel_drop_reason,
	        sk_first_photo_job_date
	FROM sale_fact_listing_flows_adjust ssf
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
		ssf.sk_first_contact_date,
	    ssf.sk_prospect_date,
	    ssf.sk_qualified_date,
	    ssf.sk_opportunity_date,
	    ssf.sk_first_listing_date,
	    ssf.sk_conversion_date,
	    ssf.sk_discard_date,
	   	sor.lead_context AS context_lead,
	    sor.prospect_context AS context_prospect,
	    sor.qualified_context AS context_qualified,
	    sor.opportunity_context AS context_opportunity,
	    sor.first_listing_context AS context_first_listing,
	    sor.sk_first_photo_job_date AS sk_first_photojob_date_fact_photo_job,
	    CASE
            WHEN ssf.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Partners'
            ELSE ssf.mkt_origin
        END AS mkt_origin,
	    ssf.mkt_completion,
	    ssf.mkt_channel,
	    CASE
            WHEN ssf.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Spinver'
            ELSE ssf.mkt_source
        END AS mkt_source,
	    ssf.mkt_medium,
	    sor.sales_company,
	    sor.sourcing_ops,
	    ssf.lead_origin,
	    ssf.funnel_drop_reason,
	    ssf.lead_context_origin,
	    ssf.has_isales_intervention,
	    ssf.sk_user_lead_affiliate,
	    'Sale' AS origin_table
	FROM sale_fact_listing_flows_adjust ssf
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
		hlf.sk_first_contact_date,
	    hlf.sk_prospect_date,
	    hlf.sk_qualified_date,
	    hlf.sk_opportunity_date,
	    hlf.sk_first_listing_date,
	    hlf.sk_conversion_date,
	    hlf.sk_discard_date,
	    sor.lead_context AS context_lead,
	    sor.prospect_context AS context_prospect,
	    sor.qualified_context AS context_qualified,
	    sor.opportunity_context AS context_opportunity,
	    sor.first_listing_context AS context_first_listing,
	    sor.sk_first_photo_job_date AS sk_first_photojob_date_fact_photo_job,
	    CASE
            WHEN hlf.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Partners'
            ELSE hlf.mkt_origin
        END AS mkt_origin,
	    hlf.mkt_completion,
	    hlf.mkt_channel,
	    CASE
            WHEN hlf.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Spinver'
            ELSE hlf.mkt_source
        END AS mkt_source,
	    hlf.mkt_medium,
	    sor.sales_company,
	    sor.sourcing_ops,
	    hlf.lead_origin,
	    hlf.funnel_drop_reason,
	    hlf.lead_context_origin,
	    hlf.has_isales_intervention,
	    hlf.sk_user_lead_affiliate,
	    'Rent' AS origin_table
	FROM fact_house_listing_flows_adjust hlf
	JOIN source_ops_rent AS sor
	  ON sor.sk_house_listing_flow = hlf.sk_house_listing_flow
), union_all AS (
SELECT *
FROM fact_rent
	UNION ALL
	SELECT *
	FROM fact_sale
)
SELECT
        *,
        row_number() OVER(PARTITION BY sk_house_listing_flow ORDER BY NULLIF(sk_prospect_date,-1)) AS aux_rn_prospect, -- column to help differentiate the prospect with equal dates
        dense_rank() OVER(PARTITION BY sk_house_listing_flow ORDER BY NULLIF(sk_prospect_date,-1)) AS aux_order_prospect,
        row_number() OVER(PARTITION BY sk_house_listing_flow ORDER BY NULLIF(sk_qualified_date,-1)) AS aux_rn_qualified, -- column to help differentiate the qualified with equal dates
        dense_rank() OVER(PARTITION BY sk_house_listing_flow ORDER BY NULLIF(sk_qualified_date,-1)) AS aux_order_qualified,
        MIN(NULLIF(sk_prospect_date,-1)) OVER(PARTITION BY sk_house_listing_flow) AS first_prospect_date,
        MAX(NULLIF(sk_prospect_date,-1)) OVER(PARTITION BY sk_house_listing_flow) AS last_prospect_date,
        MIN(NULLIF(sk_qualified_date,-1)) OVER(PARTITION BY sk_house_listing_flow) AS first_qualified_date,
        MAX(NULLIF(sk_qualified_date,-1)) OVER(PARTITION BY sk_house_listing_flow) AS last_qualified_date
FROM
    union_all