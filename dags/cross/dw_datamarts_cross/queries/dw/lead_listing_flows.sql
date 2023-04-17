WITH fact_house_listing_flows_adjust AS (
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
		hl.sk_available_qualified_date,
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
		dhl.rental_administrator,
		CASE
			WHEN dhl.is_for_rent = True
				AND dhl.consultant_type = 'CIQ_FULL' THEN 'CIQ'
			WHEN dhl.is_for_rent = True
				AND hl.mkt_origin = 'CIQ'
				AND dhl.consultant_type = 'CIQ_MANAGER' THEN 'Backend'
			WHEN hl.mkt_origin = 'CIQ'
				AND (dhl.consultant_type IS NULL
					OR dhl.consultant_type = 'Core') THEN 'Other'
			ELSE hl.mkt_origin
		END AS mkt_origin,
		dhl.ts_house_first_publication,
		CONVERT_TIMEZONE('Brazil/East', dhl.ts_house_first_publication) AS ts_house_first_publication_br_tz,
		hl.country_code,
		CASE
			WHEN om.sales_company IS NOT NULL
                THEN om.sales_company
			WHEN olc.sales_company IS NOT NULL
            	THEN olc.sales_company
            WHEN dl.sales_company = 'OLOS'
                THEN 'QUINTO_ANDAR_OUTBOUND'
            WHEN COALESCE(dl.sales_company, '') <> 'OLOS' AND du.sales_company = 'QUINTO_ANDAR'
                THEN 'QUINTO_ANDAR_INBOUND'
            ELSE COALESCE(du.sales_company, dl.sales_company)
        END AS sales_company
	FROM
		fact_house_listing_flows AS hl
	INNER JOIN
		dim_house_listing AS dhl
			ON hl.sk_house_listing = dhl.sk_house_listing
	JOIN
        dim_lead AS dl
            ON dl.sk_lead = hl.sk_lead
    LEFT JOIN
        quintoandar.dim_user_sales_rep AS du
            ON du.sk_user_sales_rep = hl.sk_user_house_registrant
	LEFT JOIN
        datalake_olos_dialer.outbound_mailing AS om
            ON om.id_lead = hl.sk_lead
	LEFT JOIN
    	datalake_olos_dialer.outbound_last_contact olc
        	ON olc.id_lead = hl.sk_lead
),
source_ops_rent AS (
	WITH photo_job AS (
	    SELECT
	        fpj.sk_house_listing,
	        MIN(fpj.sk_date_job_created) AS sk_first_photo_job_date,
            MIN(dpj.dt_job_scheduled) AS ts_first_job_scheduled,
	        SUM(CASE
					WHEN fpj.creation_origin IN ('InsideSales_internal','InsideSales_external') THEN 1
					ELSE 0
				END) AS photo_job_by_isales
	    FROM
			fact_photo_job AS fpj
	    LEFT JOIN
			public.dim_photo_job AS dpj
	        	ON fpj.id_photo_job = dpj.sk_photo_job
	    GROUP BY 1
	)
	SELECT
	    hlf.sk_house_listing_flow,
	    hlf.sk_lead,
	    hlf.sk_house_listing,
		hlf.sales_company,
	    CASE
	        WHEN hlf.mkt_origin = 'B2B'
				AND hlf.is_b2b = TRUE THEN 'B2B'
	        WHEN hlf.mkt_origin = 'CIQ' THEN 'CIQ'
	        WHEN (hlf.mkt_completion = 'Full Self-Service'
					OR (hlf.has_isales_intervention = false))
					AND (photo_job_by_isales < 1) THEN 'FSS'
	        WHEN (hlf.mkt_completion = 'Full Self-Service'
					OR (hlf.has_isales_intervention = false))
					AND photo_job_by_isales >= 1
					AND sk_first_photo_job_date = hlf.sk_opportunity_date THEN 'FSS IS PhotoJob'
	        WHEN hlf.sales_company IN ('QUINTO_ANDAR','OLOS','QUINTO_ANDAR_INBOUND','QUINTO_ANDAR_OUTBOUND','') THEN 'IS Int'
            WHEN hlf.sales_company IN ('ACTION_LINE','ATENTO','ALGAR','AEC') THEN 'IS Ext'
            ELSE 'Other'
        END AS sourcing_ops,
	    CASE
			WHEN hlf.sk_lead_date = ssf.sk_lead_date
				AND hlf.sk_lead_date > 0 THEN 'Hybrid'
	        WHEN hlf.sk_lead_date > 0 THEN 'Rent'
	        ELSE NULL
		END AS lead_context,
		CASE
			WHEN hlf.sk_prospect_date = ssf.sk_prospect_date
				AND hlf.sk_prospect_date > 0 THEN 'Hybrid'
			WHEN hlf.sk_prospect_date > 0 THEN 'Rent'
			ELSE NULL
		END AS prospect_context,
		CASE
			WHEN hlf.sk_qualified_date = ssf.sk_qualified_date
				AND hlf.sk_qualified_date > 0 THEN 'Hybrid'
			WHEN hlf.sk_qualified_date > 0  THEN 'Rent'
			ELSE NULL
		END AS qualified_context,
		CASE
			WHEN hlf.sk_available_qualified_date = ssf.sk_available_qualified_date
				AND hlf.sk_available_qualified_date > 0 THEN 'Hybrid'
			WHEN hlf.sk_available_qualified_date > 0  THEN 'Rent'
			ELSE NULL
		END AS available_qualified_context,
		CASE
			WHEN hlf.sk_opportunity_date = ssf.sk_opportunity_date
				AND hlf.sk_opportunity_date > 0 THEN 'Hybrid'
			WHEN hlf.sk_opportunity_date > 0  THEN 'Rent'
			ELSE NULL
		END AS opportunity_context,
		CASE
			WHEN hlf.sk_first_listing_date = ssf.sk_first_listing_date
				AND hlf.sk_first_listing_date > 0 THEN 'Hybrid'
			WHEN hlf.sk_first_listing_date > 0  THEN 'Rent'
			ELSE NULL
		END AS first_listing_context,
		hlf.lead_origin,
		hlf.rental_administrator,
		hlf.funnel_drop_reason,
		pj.sk_first_photo_job_date,
		pj.ts_first_job_scheduled,
		CONVERT_TIMEZONE('Brazil/East', pj.ts_first_job_scheduled) AS ts_first_job_scheduled_br_tz,
		hlf.country_code
	FROM
		fact_house_listing_flows_adjust AS hlf
	    LEFT JOIN
			photo_job AS pj
	        	ON pj.sk_house_listing = hlf.sk_house_listing
	    LEFT JOIN
			sale.fact_listing_flows AS ssf
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
		hl.sk_available_qualified_date,
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
			WHEN dl.consultant_type = 'CIQ_FULL'
				OR (dl.consultant_type='CIQ_MANAGER'
					AND dl.ts_created > dl.dt_consultant_started) THEN 'CIQ'
			ELSE hl.mkt_origin
		END AS mkt_origin,
		dl.ts_first_publication,
		CONVERT_TIMEZONE('Brazil/East', dl.ts_first_publication) AS ts_house_first_publication_br_tz,
		COALESCE(dl.is_casa_mineira_migration, false) as is_casa_mineira_migration,
		CASE
			WHEN om.sales_company IS NOT NULL
                THEN om.sales_company
			WHEN olc.sales_company IS NOT NULL
            	THEN olc.sales_company
            WHEN dim_lead.sales_company = 'OLOS'
                THEN 'QUINTO_ANDAR_OUTBOUND'
            WHEN COALESCE(dim_lead.sales_company, '') <> 'OLOS' AND du.sales_company = 'QUINTO_ANDAR'
                THEN 'QUINTO_ANDAR_INBOUND'
            ELSE COALESCE(du.sales_company, dim_lead.sales_company)
        END AS sales_company
	FROM
		sale.fact_listing_flows AS hl
	LEFT JOIN
		sale.dim_listing AS dl
			on left(hl.sk_house_listing,9) = dl.sk_house
    JOIN
        dim_lead
            ON dim_lead.sk_lead = hl.sk_lead
    LEFT JOIN
        quintoandar.dim_user_sales_rep AS du
            ON du.sk_user_sales_rep = hl.sk_user_house_registrant
	LEFT JOIN
        datalake_olos_dialer.outbound_mailing AS om
            ON om.id_lead = hl.sk_lead
	LEFT JOIN
    	datalake_olos_dialer.outbound_last_contact olc
        	ON olc.id_lead = hl.sk_lead
),
source_ops_sale AS (
	with photo_job AS (
	    SELECT
	        fpj.sk_house_listing,
	        MIN(fpj.sk_date_job_created) AS sk_first_photo_job_date,
            MIN(dpj.dt_job_scheduled) AS ts_first_job_scheduled,
	        SUM(CASE
					WHEN fpj.creation_origin IN ('InsideSales_internal','InsideSales_external') THEN 1
					ELSE 0
				END) AS photo_job_by_isales
	    FROM
			fact_photo_job AS fpj
	    LEFT JOIN
			public.dim_photo_job AS dpj
	        	ON fpj.id_photo_job = dpj.sk_photo_job
	    GROUP BY 1
	)
	SELECT
	    ssf.sk_house_listing_flow,
	    ssf.sk_lead,
	    ssf.sk_house_listing,
		ssf.sales_company,
	    CASE
	        WHEN ssf.mkt_origin = 'B2B'
				AND ssf.is_b2b = TRUE THEN 'B2B'
	        WHEN ssf.mkt_origin = 'CIQ' THEN 'CIQ'
	        WHEN (ssf.mkt_completion = 'Full Self-Service'
					OR (ssf.has_isales_intervention = false))
				AND (photo_job_by_isales < 1) THEN 'FSS'
	        WHEN (ssf.mkt_completion = 'Full Self-Service'
					OR (ssf.has_isales_intervention = false))
				AND photo_job_by_isales >= 1
				AND sk_first_photo_job_date = ssf.sk_opportunity_date THEN 'FSS IS PhotoJob'
	        WHEN ssf.sales_company IN ('QUINTO_ANDAR','OLOS','QUINTO_ANDAR_INBOUND','QUINTO_ANDAR_OUTBOUND','') THEN 'IS Int'
            WHEN ssf.sales_company IN ('ACTION_LINE','ATENTO','ALGAR','AEC') THEN 'IS Ext'
            ELSE 'Other'
        END AS sourcing_ops,
		CASE
			WHEN hlf.sk_lead_date = ssf.sk_lead_date
				AND ssf.sk_lead_date > 0 THEN 'Hybrid'
			WHEN ssf.sk_lead_date > 0 THEN 'Sale'
			ELSE NULL
		END AS lead_context,
		CASE
			WHEN hlf.sk_prospect_date = ssf.sk_prospect_date
				AND ssf.sk_prospect_date > 0 THEN 'Hybrid'
			WHEN ssf.sk_prospect_date > 0 THEN 'Sale'
			ELSE NULL
		END AS prospect_context,
		CASE
			WHEN hlf.sk_qualified_date = ssf.sk_qualified_date
				AND ssf.sk_qualified_date > 0 THEN 'Hybrid'
			WHEN ssf.sk_qualified_date > 0  THEN 'Sale'
			ELSE NULL
		END AS qualified_context,
		CASE
			WHEN hlf.sk_available_qualified_date = ssf.sk_available_qualified_date
				AND ssf.sk_available_qualified_date > 0 THEN 'Hybrid'
			WHEN ssf.sk_available_qualified_date > 0  THEN 'Sale'
			ELSE NULL
		END AS available_qualified_context,
		CASE
			WHEN hlf.sk_opportunity_date = ssf.sk_opportunity_date
				AND ssf.sk_opportunity_date > 0 THEN 'Hybrid'
			WHEN ssf.sk_opportunity_date > 0  THEN 'Sale'
			ELSE NULL
		END AS opportunity_context,
		CASE
			WHEN hlf.sk_first_listing_date = ssf.sk_first_listing_date
				AND ssf.sk_first_listing_date > 0 THEN 'Hybrid'
			WHEN ssf.sk_first_listing_date > 0  THEN 'Sale'
			ELSE NULL
		END AS first_listing_context,
		ssf.lead_origin,
		ssf.funnel_drop_reason,
		sk_first_photo_job_date,
		pj.ts_first_job_scheduled,
		CONVERT_TIMEZONE('Brazil/East', pj.ts_first_job_scheduled) AS ts_first_job_scheduled_br_tz,
		dhl.rental_administrator
	FROM
		sale_fact_listing_flows_adjust AS ssf
	    LEFT JOIN
			photo_job AS pj
	        	ON pj.sk_house_listing = ssf.sk_house_listing
	    LEFT JOIN
			fact_house_listing_flows AS hlf
	        	ON hlf.sk_house_listing_flow = ssf.sk_house_listing_flow
	    LEFT JOIN
			dim_house_listing AS dhl
	        ON dhl.sk_house_listing = hlf.sk_house_listing
		where ssf.is_casa_mineira_migration = false
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
	    ssf.sk_available_qualified_date,
	    ssf.sk_opportunity_date,
	    ssf.sk_first_listing_date,
	    ssf.sk_conversion_date,
	    ssf.sk_discard_date,
	   	sor.lead_context AS context_lead,
	    sor.prospect_context AS context_prospect,
	    sor.qualified_context AS context_qualified,
	    sor.available_qualified_context AS context_available_qualified,
	    sor.opportunity_context AS context_opportunity,
	    sor.first_listing_context AS context_first_listing,
	    sor.sk_first_photo_job_date AS sk_first_photojob_date_fact_photo_job,
	    sor.ts_first_job_scheduled,
	    sor.ts_first_job_scheduled_br_tz,
		ssf.ts_first_publication,
		ssf.ts_house_first_publication_br_tz,
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
	    'Sale' AS origin_table,
	    sor.rental_administrator,
		NULL AS country_code
	FROM
		sale_fact_listing_flows_adjust AS ssf
	JOIN
		source_ops_sale AS sor
	  		ON sor.sk_house_listing_flow = ssf.sk_house_listing_flow
	where ssf.is_casa_mineira_migration = false
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
	    hlf.sk_available_qualified_date,
	    hlf.sk_opportunity_date,
	    hlf.sk_first_listing_date,
	    hlf.sk_conversion_date,
	    hlf.sk_discard_date,
	    sor.lead_context AS context_lead,
	    sor.prospect_context AS context_prospect,
	    sor.qualified_context AS context_qualified,
	    sor.available_qualified_context AS context_available_qualified,
	    sor.opportunity_context AS context_opportunity,
	    sor.first_listing_context AS context_first_listing,
	    sor.sk_first_photo_job_date AS sk_first_photojob_date_fact_photo_job,
	    sor.ts_first_job_scheduled,
	    sor.ts_first_job_scheduled_br_tz,
		hlf.ts_house_first_publication as ts_first_publication,
		hlf.ts_house_first_publication_br_tz,
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
	    'Rent' AS origin_table,
	    hlf.rental_administrator,
		hlf.country_code
	FROM
		fact_house_listing_flows_adjust AS hlf
	JOIN
		source_ops_rent AS sor
	  		ON sor.sk_house_listing_flow = hlf.sk_house_listing_flow
),
union_all AS (
	SELECT
        *
	FROM
		fact_rent
	UNION ALL
	SELECT
        *
	FROM
		fact_sale
)
SELECT
	sk_house_listing_flow,
	sk_lead,
	CAST(LEFT(sk_house_listing,9) AS BIGINT) AS sk_house,
	sk_house_listing,
	sk_region,
	sk_lead_date,
	sk_first_contact_date,
	sk_prospect_date,
	sk_qualified_date,
	sk_available_qualified_date,
	sk_opportunity_date,
	sk_first_listing_date,
	sk_conversion_date,
	sk_discard_date,
	sk_first_photojob_date_fact_photo_job,
	sk_user_lead_affiliate,
	country_code,
	context_lead,
	context_prospect,
	context_qualified,
	context_available_qualified,
	context_opportunity,
	context_first_listing,
	mkt_origin,
	mkt_completion,
	mkt_channel,
	mkt_source,
	mkt_medium,
	sales_company,
	sourcing_ops,
	lead_origin,
	funnel_drop_reason,
	lead_context_origin,
	origin_table,
	rental_administrator,
	ROW_NUMBER() OVER(PARTITION BY sk_house_listing_flow ORDER BY NULLIF(sk_prospect_date,-1)) AS aux_rn_prospect, -- column to help differentiate the prospect with equal dates
	DENSE_RANK() OVER(PARTITION BY sk_house_listing_flow ORDER BY NULLIF(sk_prospect_date,-1)) AS aux_order_prospect,
	ROW_NUMBER() OVER(PARTITION BY sk_house_listing_flow ORDER BY NULLIF(sk_qualified_date,-1)) AS aux_rn_qualified, -- column to help differentiate the qualified with equal dates
	DENSE_RANK() OVER(PARTITION BY sk_house_listing_flow ORDER BY NULLIF(sk_qualified_date,-1)) AS aux_order_qualified,
	ROW_NUMBER() OVER(PARTITION BY sk_house_listing_flow ORDER BY NULLIF(sk_available_qualified_date,-1)) AS aux_rn_available_qualified, -- column to help differentiate the available qualified with equal dates
	DENSE_RANK() OVER(PARTITION BY sk_house_listing_flow ORDER BY NULLIF(sk_available_qualified_date,-1)) AS aux_order_available_qualified,
	MIN(NULLIF(sk_prospect_date,-1)) OVER(PARTITION BY sk_house_listing_flow) AS first_prospect_date,
	MAX(NULLIF(sk_prospect_date,-1)) OVER(PARTITION BY sk_house_listing_flow) AS last_prospect_date,
	MIN(NULLIF(sk_qualified_date,-1)) OVER(PARTITION BY sk_house_listing_flow) AS first_qualified_date,
	MAX(NULLIF(sk_qualified_date,-1)) OVER(PARTITION BY sk_house_listing_flow) AS last_qualified_date,
	MIN(NULLIF(sk_available_qualified_date,-1)) OVER(PARTITION BY sk_house_listing_flow) AS first_available_qualified_date,
	MAX(NULLIF(sk_available_qualified_date,-1)) OVER(PARTITION BY sk_house_listing_flow) AS last_available_qualified_date,
	has_isales_intervention,
	ts_first_job_scheduled,
	ts_first_job_scheduled_br_tz,
	ts_first_publication,
	ts_house_first_publication_br_tz
FROM
    union_all