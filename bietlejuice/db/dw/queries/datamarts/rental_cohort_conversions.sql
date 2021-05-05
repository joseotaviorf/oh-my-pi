WITH
l2p AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' OR fhlf.mkt_origin = 'CIQ' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	CASE
    	WHEN sourcing_ops IN ('IS Ext', 'IS Int', 'FSS IS PhotoJob', 'Other') AND lead_context IN ('FSS','IS') THEN 'IS'
	    ELSE sourcing_ops
    END AS lead_processing_operation,
	NULL AS demand_mkt_channel,
	NULL AS demand_mkt_medium,
	NULL AS first_touchpoint,
	NULL::BOOLEAN AS is_guarantee,
	CASE
	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_lead_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_prospect_date,-1)))) < 0
	        THEN 'W5+'
	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_lead_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_prospect_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_lead_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_prospect_date,-1))))
	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_lead_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_prospect_date,-1)))) >=5
	        THEN 'W5+'
	END AS weeks_conversion,
  	COUNT(fhlf.sk_lead_date) AS l2p,
	NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2opp,
	NULL::BIGINT AS opp2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc,
  	NULL::BIGINT AS vc2os,
  	NULL::BIGINT AS os2oa,
  	NULL::BIGINT AS oa2cei,
  	NULL::BIGINT AS oa2da,
  	NULL::BIGINT AS oa2ds,
  	NULL::BIGINT AS cei2cep,
  	NULL::BIGINT AS cei2gs,
  	NULL::BIGINT AS cep2ds,
  	NULL::BIGINT AS gs2ds,
  	NULL::BIGINT AS ds2da,
  	NULL::BIGINT AS da2cc,
  	NULL::BIGINT AS da2gp,
  	NULL::BIGINT AS gp2cc,
  	NULL::BIGINT AS da2cs,
  	NULL::BIGINT AS da_gp2cs,
  	NULL::BIGINT AS cc2cs,
  	NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    datamarts.lead_listing_flows fhlf
        ON dd.sk_date = fhlf.sk_lead_date
        AND fhlf.sk_lead_date > 0
LEFT JOIN
    dim_region dr
        ON dr.sk_region = fhlf.sk_region
WHERE
    fhlf.origin_table = 'Rent'
    AND dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
p2q AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' OR fhlf.mkt_origin = 'CIQ' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	CASE
    	WHEN sourcing_ops IN ('IS Ext', 'IS Int', 'FSS IS PhotoJob', 'Other') AND lead_context IN ('FSS','IS') THEN 'IS'
	    ELSE sourcing_ops
    END AS lead_processing_operation,
	NULL AS demand_mkt_channel,
	NULL AS demand_mkt_medium,
	NULL AS first_touchpoint,
	NULL::BOOLEAN AS is_guarantee,
	CASE
	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_qualified_date,-1)))) < 0
	        THEN 'W5+'
	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_qualified_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_qualified_date,-1))))
	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_qualified_date,-1)))) >= 5
	        THEN 'W5+'
	END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	COUNT(fhlf.sk_prospect_date) AS p2q, -- this count is done on the prospect date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS q2opp,
	NULL::BIGINT AS opp2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc,
  	NULL::BIGINT AS vc2os,
  	NULL::BIGINT AS os2oa,
  	NULL::BIGINT AS oa2cei,
  	NULL::BIGINT AS oa2da,
  	NULL::BIGINT AS oa2ds,
  	NULL::BIGINT AS cei2cep,
  	NULL::BIGINT AS cei2gs,
  	NULL::BIGINT AS cep2ds,
  	NULL::BIGINT AS gs2ds,
  	NULL::BIGINT AS ds2da,
  	NULL::BIGINT AS da2cc,
  	NULL::BIGINT AS da2gp,
  	NULL::BIGINT AS gp2cc,
  	NULL::BIGINT AS da2cs,
  	NULL::BIGINT AS da_gp2cs,
  	NULL::BIGINT AS cc2cs,
  	NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    datamarts.lead_listing_flows fhlf
        ON dd.sk_date = fhlf.sk_prospect_date
        AND fhlf.sk_prospect_date > 0
LEFT JOIN
    dim_region dr
        ON dr.sk_region = fhlf.sk_region
WHERE
    fhlf.origin_table = 'Rent'
    AND dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
q2opp AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' OR fhlf.mkt_origin = 'CIQ' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	CASE
    	WHEN sourcing_ops IN ('IS Ext', 'IS Int', 'FSS IS PhotoJob', 'Other') AND lead_context IN ('FSS','IS') THEN 'IS'
	    ELSE sourcing_ops
    END AS lead_processing_operation,
	NULL AS demand_mkt_channel,
	NULL AS demand_mkt_medium,
	NULL AS first_touchpoint,
	NULL::BOOLEAN AS is_guarantee,
	CASE
	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_opportunity_date,-1)))) < 0
	        THEN 'W5+'
	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_opportunity_date,-1)))) BETWEEN 0 AND 4
		    THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_opportunity_date,-1))))
		WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_opportunity_date,-1)))) >= 5
		    THEN 'W5+'
	END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	NULL::BIGINT AS p2q,
	COUNT(fhlf.sk_qualified_date) AS q2opp, -- this count is done on the qualified date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS opp2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc,
  	NULL::BIGINT AS vc2os,
  	NULL::BIGINT AS os2oa,
  	NULL::BIGINT AS oa2cei,
  	NULL::BIGINT AS oa2da,
  	NULL::BIGINT AS oa2ds,
  	NULL::BIGINT AS cei2cep,
  	NULL::BIGINT AS cei2gs,
  	NULL::BIGINT AS cep2ds,
  	NULL::BIGINT AS gs2ds,
  	NULL::BIGINT AS ds2da,
  	NULL::BIGINT AS da2cc,
  	NULL::BIGINT AS da2gp,
  	NULL::BIGINT AS gp2cc,
  	NULL::BIGINT AS da2cs,
  	NULL::BIGINT AS da_gp2cs,
  	NULL::BIGINT AS cc2cs,
  	NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    datamarts.lead_listing_flows fhlf
        ON dd.sk_date = fhlf.sk_qualified_date
        AND fhlf.sk_qualified_date > 0
LEFT JOIN
    dim_region dr
        ON dr.sk_region = fhlf.sk_region
WHERE
    fhlf.origin_table = 'Rent'
    AND dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
opp2fl AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' OR fhlf.mkt_origin = 'CIQ' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	CASE
    	WHEN sourcing_ops IN ('IS Ext', 'IS Int', 'FSS IS PhotoJob', 'Other') AND lead_context IN ('FSS','IS') THEN 'IS'
	    ELSE sourcing_ops
    END AS lead_processing_operation,
	NULL AS demand_mkt_channel,
	NULL AS demand_mkt_medium,
	NULL AS first_touchpoint,
	NULL::BOOLEAN AS is_guarantee,
  	CASE
  	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_first_listing_date,-1)))) < 0
  	        THEN 'W5+'
	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_first_listing_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_first_listing_date,-1))))
	    WHEN datediff('week',DATE_TRUNC('week',DATE(fhlf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(fhlf.sk_first_listing_date,-1)))) >= 5
	        THEN 'W5+'
	END AS weeks_conversion,
  	NULL::BIGINT AS l2p,
	NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2opp,
	COUNT(DISTINCT fhlf.sk_house_listing) AS opp2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc,
  	NULL::BIGINT AS vc2os,
  	NULL::BIGINT AS os2oa,
  	NULL::BIGINT AS oa2cei,
  	NULL::BIGINT AS oa2ds,
  	NULL::BIGINT AS oa2da,
  	NULL::BIGINT AS cei2cep,
  	NULL::BIGINT AS cei2gs,
  	NULL::BIGINT AS cep2ds,
  	NULL::BIGINT AS gs2da,
  	NULL::BIGINT AS ds2ds,
  	NULL::BIGINT AS da2cc,
  	NULL::BIGINT AS da2gp,
  	NULL::BIGINT AS gp2cc,
  	NULL::BIGINT AS da2cs,
  	NULL::BIGINT AS da_gp2cs,
  	NULL::BIGINT AS cc2cs,
  	NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    datamarts.lead_listing_flows fhlf
        ON dd.sk_date = fhlf.sk_opportunity_date
        AND fhlf.sk_opportunity_date > 0
LEFT JOIN
    dim_region dr
        ON dr.sk_region = fhlf.sk_region
WHERE
    fhlf.origin_table = 'Rent'
    AND dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
rent_flow_adjusted AS (
SELECT
    rf.sk_rent_flow,
    rf.sk_house_listing,
    rf.sk_client,
    rf.sk_region,
    rf.sk_visit_date,
    rf.flg_visit_completed,
    rf.sk_proposal,
    rf.sk_contract_annulment_date,
    rf.sk_booking,
    rf.sk_booking_created_date,
    rf.sk_offer,
    rf.sk_offer_submitted_date,
    rf.sk_offer_approved_date,
    rf.sk_first_credit_evaluation_init,
    rf.sk_first_credit_evaluation_positive,
    rf.sk_guarantee_date,
    rf.sk_tenant_first_doc_sent_date,
    rf.sk_last_doc_analysis_approved,
    rf.sk_credit_analysis_init_date,
    rf.sk_credit_analysis_end_date,
    rf.sk_guarantee_paid_date,
    rf.sk_credit_analysis_approved_date,
    COALESCE(nullif(rf.sk_last_doc_analysis_approved, -1),rf.sk_credit_analysis_approved_date) as sk_credit_analysis_approved_date_adjust, -- consider credit approved date to historical data (before 8/jun)
    COALESCE(nullif(rf.sk_guarantee_paid_date,-1),rf.sk_credit_analysis_approved_date) as sk_da_gp_date_adjust, -- consider guarantee paid date as the date of credit approved
    rf.sk_contract,
    rf.sk_contract_created_date,
    rf.sk_contract_signed_date,
    fdf.funnel_flow,
    fdf.funnel_first_touchpoint,
    fdf.had_flow_visit,
    fdf.had_flow_direct,
    fdf.had_flow_tta,
    fdf.flow_type,
    dp.guarantee,
    CASE
        WHEN dhl.is_b2b = TRUE THEN 'B2B'
        WHEN ciq.sk_house_listing IS NOT NULL THEN 'CIQ'
        WHEN dhl.is_b2b = FALSE OR ciq.sk_house_listing IS NULL THEN 'FALSE'
    END AS is_b2b,
    dr.city_group,
    db.mkt_channel AS demand_mkt_channel_booking,
    db.mkt_medium AS demand_mkt_medium_booking,
    dof.mkt_channel AS demand_mkt_channel_offer,
    dof.mkt_medium AS demand_mkt_medium_offer
FROM
    fact_listing_rent_flows rf
LEFT JOIN
    dim_proposal dp
        ON rf.sk_proposal = dp.sk_proposal
JOIN
    dim_house_listing dhl
        ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN
    dim_booking db
        ON rf.sk_booking = db.sk_booking
LEFT JOIN
    dim_region dr
        ON rf.sk_region = dr.sk_region
LEFT JOIN
    dim_offer dof
        ON rf.sk_offer = dof.sk_offer
LEFT JOIN
    datamarts.funnel_demand_flows fdf
        ON rf.sk_rent_flow = fdf.sk_rent_flow
LEFT JOIN
    datamarts.quintoandar_consultant_listings ciq
        ON rf.sk_house_listing = ciq.sk_house_listing
),
vb2vc AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_booking AS demand_mkt_channel,
  rf.demand_mkt_medium_booking AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  NULL::BOOLEAN AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_booking_created_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_visit_date,-1)))) < 0 AND rf.flg_visit_completed
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_booking_created_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_visit_date,-1)))) BETWEEN 0 AND 4 AND rf.flg_visit_completed
	       THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_booking_created_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_visit_date,-1))))
	  WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_booking_created_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_visit_date,-1)))) >= 5 AND rf.flg_visit_completed
	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  COUNT(DISTINCT rf.sk_booking) AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_booking_created_date
        AND rf.sk_booking_created_date > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
vc AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_booking AS demand_mkt_channel,
  rf.demand_mkt_medium_booking AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  NULL::BOOLEAN AS is_guarantee,
  NULL::VARCHAR AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  COUNT(DISTINCT rf.sk_booking) AS vc,
  NULL::BIGINT vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_visit_date
        AND rf.sk_visit_date > 0 AND rf.flg_visit_completed = 1
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13
),
vc2os AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_booking AS demand_mkt_channel,
  rf.demand_mkt_medium_booking AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  NULL::BOOLEAN AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_visit_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_offer_submitted_date,-1)))) < 0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_visit_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_offer_submitted_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_visit_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_offer_submitted_date,-1))))
	  WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_visit_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_offer_submitted_date,-1)))) >= 5
	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  COUNT(DISTINCT rf.sk_offer) vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_visit_date
        AND rf.sk_visit_date > 0 AND rf.flg_visit_completed = 1
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
os2oa AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  NULL::BOOLEAN AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_submitted_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_offer_approved_date,-1)))) < 0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_submitted_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_offer_approved_date,-1)))) BETWEEN 0 AND 4
           THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_submitted_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_offer_approved_date,-1))))
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_submitted_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_offer_approved_date,-1)))) >= 5
           THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  COUNT(DISTINCT rf.sk_offer) AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_offer_submitted_date
        AND rf.sk_offer_submitted_date > 0
WHERE
     dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
oa2cei AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  NULL::BOOLEAN AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_first_credit_evaluation_init,-1)))) < 0
           THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_first_credit_evaluation_init,-1)))) BETWEEN 0 AND 4
           THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_first_credit_evaluation_init,-1))))
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_first_credit_evaluation_init,-1)))) >=5
           THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  COUNT(DISTINCT rf.sk_offer) AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_offer_approved_date
        AND rf.sk_offer_approved_date > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
oa2da AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  NULL::BOOLEAN AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_credit_analysis_approved_date_adjust,-1)))) < 0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_credit_analysis_approved_date_adjust,-1)))) BETWEEN 0 AND 4
           THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_credit_analysis_approved_date_adjust,-1))))
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_credit_analysis_approved_date_adjust,-1)))) >= 5
           THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  COUNT(DISTINCT rf.sk_offer) AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_offer_approved_date
        AND rf.sk_offer_approved_date > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
oa2ds AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  NULL::BOOLEAN AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1)))) < 0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1)))) BETWEEN 0 AND 4
           THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1))))
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_offer_approved_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1)))) >= 5
           THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  COUNT(DISTINCT rf.sk_offer) AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_offer_approved_date
        AND rf.sk_offer_approved_date > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
cei2cep AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_init)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_first_credit_evaluation_positive,-1)))) < 0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_init)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_first_credit_evaluation_positive,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_init)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_first_credit_evaluation_positive,-1))))
	  WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_init)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_first_credit_evaluation_positive,-1)))) >=5
	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  COUNT(DISTINCT rf.sk_offer) AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_first_credit_evaluation_init
        AND rf.sk_first_credit_evaluation_init > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
        AND rf.guarantee != 'RentalGuarantee'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9,10, 11, 12, 13
),
cei2gs AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_init)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_guarantee_date,-1)))) < 0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_init)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_guarantee_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_init)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_guarantee_date,-1))))
	  WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_init)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_guarantee_date,-1)))) >=5
	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  COUNT(DISTINCT rf.sk_offer) AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_first_credit_evaluation_init
        AND rf.sk_first_credit_evaluation_init > 0
WHERE
     dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
         AND rf.guarantee = 'RentalGuarantee'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9,10, 11, 12, 13
),
cep2ds AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_positive)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1)))) < 0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_positive)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1)))) BETWEEN 0 AND 4
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_positive)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1))))
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_first_credit_evaluation_positive)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1)))) >=5
            THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  COUNT(DISTINCT rf.sk_offer) AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_first_credit_evaluation_positive
        AND rf.sk_first_credit_evaluation_positive > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
        AND rf.guarantee != 'RentalGuarantee'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
gs2ds AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_guarantee_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1)))) < 0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_guarantee_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_guarantee_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1))))
	  WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_guarantee_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_tenant_first_doc_sent_date,-1)))) >=5
	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  COUNT(DISTINCT rf.sk_offer) AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_guarantee_date
        AND rf.sk_guarantee_date > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
        AND rf.guarantee = 'RentalGuarantee'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
ds2da AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_tenant_first_doc_sent_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_credit_analysis_approved_date_adjust,-1)))) < 0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_tenant_first_doc_sent_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_credit_analysis_approved_date_adjust,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_tenant_first_doc_sent_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_credit_analysis_approved_date_adjust,-1))))
	  WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_tenant_first_doc_sent_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_credit_analysis_approved_date_adjust,-1)))) >=5
	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  COUNT(DISTINCT rf.sk_offer) AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_tenant_first_doc_sent_date
        AND rf.sk_tenant_first_doc_sent_date > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
da2cc AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_created_date,-1)))) <0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_created_date,-1)))) BETWEEN 0 AND 4
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_created_date,-1))))
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_created_date,-1)))) >= 5
            THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  COUNT(DISTINCT rf.sk_offer) AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_credit_analysis_approved_date_adjust
        AND rf.sk_credit_analysis_approved_date_adjust > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
        AND rf.guarantee != 'RentalGuarantee'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
da2gp AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_guarantee_paid_date,-1)))) <0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_guarantee_paid_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_guarantee_paid_date,-1))))
	  WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_guarantee_paid_date,-1)))) >= 5
	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  COUNT(DISTINCT rf.sk_offer) AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_credit_analysis_approved_date_adjust
        AND rf.sk_credit_analysis_approved_date_adjust > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
        AND rf.guarantee = 'RentalGuarantee'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
gp2cc AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_guarantee_paid_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_created_date,-1)))) <0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_guarantee_paid_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_created_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_guarantee_paid_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_created_date,-1))))
	  WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_guarantee_paid_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_created_date,-1)))) >=5
	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  COUNT(DISTINCT rf.sk_offer) AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_guarantee_paid_date
        AND rf.sk_guarantee_paid_date > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
        AND rf.guarantee = 'RentalGuarantee'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9,10, 11, 12, 13
),
da2cs AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1)))) < 0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1)))) BETWEEN 0 AND 4
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1))))
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_credit_analysis_approved_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1)))) >=5
            THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  COUNT(DISTINCT rf.sk_offer) AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_credit_analysis_approved_date_adjust
        AND rf.sk_credit_analysis_approved_date_adjust > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9,10, 11, 12, 13
),
da_gp2cs AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_da_gp_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1)))) <0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_da_gp_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1)))) BETWEEN 0 AND 4
  	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_da_gp_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1))))
  	  WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_da_gp_date_adjust)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1))))>= 5
  	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  COUNT(DISTINCT rf.sk_offer) AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_da_gp_date_adjust
        AND rf.sk_da_gp_date_adjust > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9,10, 11, 12,13
),
cc2cs AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_contract_created_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1)))) <0
            THEN 'W5+'
      WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_contract_created_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_contract_created_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1))))
	  WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_contract_created_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_signed_date,-1))))>= 5
	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  COUNT(DISTINCT rf.sk_contract) AS cc2cs,
  NULL::BIGINT AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_contract_created_date
        AND rf.sk_contract_created_date > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),
cs2ce AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  NULL AS lead_processing_operation,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_contract_signed_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_annulment_date,-1)))) <0
            THEN 'W5+'
        WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_contract_signed_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_annulment_date,-1)))) BETWEEN 0 AND 4
	        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(rf.sk_contract_signed_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_annulment_date,-1))))
        WHEN datediff('week',DATE_TRUNC('week',DATE(rf.sk_contract_signed_date)),DATE_TRUNC('week',DATE(NULLIF(rf.sk_contract_annulment_date,-1)))) >= 5
	        THEN 'W5+'
  END AS weeks_conversion,
  NULL::BIGINT AS l2p,
  NULL::BIGINT AS p2q,
  NULL::BIGINT AS q2opp,
  NULL::BIGINT AS opp2fl,
  NULL::BIGINT AS vb2vc,
  NULL::BIGINT AS vc,
  NULL::BIGINT AS vc2os,
  NULL::BIGINT AS os2oa,
  NULL::BIGINT AS oa2cei,
  NULL::BIGINT AS oa2da,
  NULL::BIGINT AS oa2ds,
  NULL::BIGINT AS cei2cep,
  NULL::BIGINT AS cei2gs,
  NULL::BIGINT AS cep2ds,
  NULL::BIGINT AS gs2ds,
  NULL::BIGINT AS ds2da,
  NULL::BIGINT AS da2cc,
  NULL::BIGINT AS da2gp,
  NULL::BIGINT AS gp2cc,
  NULL::BIGINT AS da2cs,
  NULL::BIGINT AS da_gp2cs,
  NULL::BIGINT AS cc2cs,
  COUNT(DISTINCT rf.sk_contract) AS cs2ce
FROM
    dim_date dd
JOIN
    rent_flow_adjusted rf
        ON dd.sk_date = rf.sk_contract_signed_date
        AND rf.sk_contract_signed_date > 0
WHERE
    dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
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
	SELECT * FROM vb2vc
	UNION ALL
	SELECT * FROM vc
	UNION ALL
	SELECT * FROM vc2os
	UNION ALL
	SELECT * FROM os2oa
	UNION ALL
	SELECT * FROM oa2cei
	UNION ALL
	SELECT * FROM oa2da
	UNION ALL
	SELECT * FROM oa2ds
	UNION ALL
	SELECT * FROM cei2cep
	UNION ALL
	SELECT * FROM cei2gs
	UNION ALL
	SELECT * FROM cep2ds
	UNION ALL
	SELECT * FROM gs2ds
	UNION ALL
	SELECT * FROM ds2da
	UNION ALL
	SELECT * FROM da2cc
	UNION ALL
	SELECT * FROM da2gp
	UNION ALL
	SELECT * FROM gp2cc
	UNION ALL
	SELECT * FROM da2cs
	UNION ALL
	SELECT * FROM da_gp2cs
	UNION ALL
	SELECT * FROM cc2cs
	UNION ALL
	SELECT * FROM cs2ce
),
union_all_date AS (
SELECT
  dd."date",
  ua.city_group,
  ua.is_b2b,
  ua.supply_mkt_origin,
  ua.supply_mkt_channel,
  ua.lead_context,
  ua.lead_processing_operation,
  ua.demand_mkt_channel,
  ua.demand_mkt_medium,
  ua.first_touchpoint,
  ua.is_guarantee,
  ua.weeks_conversion,
  ua.l2p,
  ua.p2q,
  ua.q2opp,
  ua.opp2fl,
  ua.vb2vc,
  ua.vc,
  ua.vc2os,
  ua.os2oa,
  ua.oa2cei,
  ua.oa2da,
  ua.oa2ds,
  ua.cei2cep,
  ua.cei2gs,
  ua.cep2ds,
  ua.gs2ds,
  ua.ds2da,
  ua.da2cc,
  ua.da2gp,
  ua.gp2cc,
  ua.da2cs,
  ua.da_gp2cs,
  ua.cc2cs,
  ua.cs2ce
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
        WHEN supply_mkt_origin = 'Owner PWA' THEN supply_mkt_channel
        WHEN supply_mkt_origin != 'Owner PWA' THEN supply_mkt_origin
    END AS supply_mkt_origin_detailed,
    lead_context,
    lead_processing_operation,
    CASE
        WHEN demand_mkt_channel in ('Not Mapped', 'Other') OR demand_mkt_channel IS NULL THEN 'Other'
        ELSE demand_mkt_channel
    END AS demand_mkt_channel,
    CASE
         WHEN demand_mkt_channel in ('Not Mapped', 'Other') OR demand_mkt_channel is NULL THEN 'Other'
         WHEN demand_mkt_channel in ('Online Classifieds','Agents') THEN demand_mkt_channel
         WHEN demand_mkt_medium in ('SEO branded', 'SEO non-branded') THEN 'SEO'
         ELSE demand_mkt_medium
    END AS demand_mkt_channel_detailed,
    first_touchpoint,
    is_guarantee,
    is_b2b AS is_b2b_demand,
    weeks_conversion AS weeks_conversion,
    SUM(COALESCE(l2p,0)) AS l2p,
    SUM(COALESCE(p2q,0)) AS p2q,
    SUM(COALESCE(q2opp,0)) AS q2opp,
    SUM(COALESCE(opp2fl,0)) AS opp2fl,
    SUM(COALESCE(vb2vc,0)) AS vb2vc,
    SUM(COALESCE(vc,0)) AS vc,
    SUM(COALESCE(vc2os,0)) AS vc2os,
    SUM(COALESCE(os2oa,0)) AS os2oa,
    SUM(COALESCE(oa2cei,0)) AS oa2cei,
    SUM(COALESCE(oa2da,0)) AS oa2ca,
    SUM(COALESCE(oa2ds,0)) AS oa2ds,
    SUM(COALESCE(cei2cep,0)) AS cei2cep,
    SUM(COALESCE(cei2gs,0)) AS cei2gs,
    SUM(COALESCE(cep2ds,0)) AS cep2ds,
    SUM(COALESCE(gs2ds,0)) AS gs2ds,
    SUM(COALESCE(ds2da,0)) AS ds2ca,
    SUM(COALESCE(da2cc,0)) AS ca2cc,
    SUM(COALESCE(da2gp,0)) AS ca2gp,
    SUM(COALESCE(gp2cc,0)) AS gp2cc,
    SUM(COALESCE(da2cs,0)) AS ca2cs,
    SUM(COALESCE(da_gp2cs,0)) AS ca_gp2cs,
    SUM(COALESCE(cc2cs,0)) AS cc2cs,
    SUM(COALESCE(cs2ce,0)) AS cs2ce,
    current_timestamp AS ts_load
FROM
    union_all
GROUP BY "date", city_group, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
ORDER BY 1 DESC