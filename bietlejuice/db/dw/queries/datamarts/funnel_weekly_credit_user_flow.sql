WITH rent_flows_base AS (
    SELECT
        sk_rent_flow,
        sk_house_listing,
        sk_region,
        sk_client,
        sk_offer,
        sk_proposal,
        sk_contract,
        sk_offer_submitted_date,
        sk_offer_approved_date,
        sk_last_credit_evaluation_init,
        sk_last_credit_evaluation_positive,
        sk_last_credit_evaluation_negative,
        sk_tenant_first_doc_sent_date,
        sk_tenant_doc_complete_date,
        sk_credit_analysis_approved_date,
        sk_guarantee_paid_date,
        sk_contract_created_date,
        sk_contract_signed_date,
        funnel_step
    FROM 
        fact_listing_rent_flows AS f
    INNER JOIN 
        dim_date AS dd
            ON f.sk_offer_approved_date = dd.sk_date
    WHERE
        dd.date >= '2020-01-01'
    ),

events_dates AS (
    SELECT
        rfb.sk_proposal,
        dd_os.date AS offer_submitted_date,
        dd_oa.date AS offer_approved_date,
        dd_es.date AS last_evaluation_started_date,
        COALESCE(
            dd_evp.date,
            CASE
                WHEN sk_last_credit_evaluation_positive < 0 
                AND sk_last_credit_evaluation_negative > 0 
                AND dp.guarantee = 'RentalGuarantee' THEN dd_evn.date 
            END
        ) AS evaluation_approved_date,
        dd_ds.date AS document_first_sent_date,
        dd_dc.date AS document_completed_date,
        dd_da.date AS credit_analysis_approved_date,
        dd_guarantee.date AS guarantee_paid_date,
        dd_cc.date AS contract_created_date,
        dd_cs.date AS contract_signed_date
    FROM 
        rent_flows_base AS rfb
    INNER JOIN 
        dim_proposal AS dp
            ON rfb.sk_proposal = dp.sk_proposal
    INNER JOIN 
        dim_date AS dd_os
            ON rfb.sk_offer_submitted_date = dd_os.sk_date
    INNER JOIN 
        dim_date AS dd_oa
            ON rfb.sk_offer_approved_date = dd_oa.sk_date
    INNER JOIN 
        dim_date AS dd_es
            ON rfb.sk_last_credit_evaluation_init = dd_es.sk_date
    INNER JOIN 
        dim_date AS dd_evp
            ON rfb.sk_last_credit_evaluation_positive = dd_evp.sk_date
    INNER JOIN 
        dim_date AS dd_evn
            ON rfb.sk_last_credit_evaluation_negative = dd_evn.sk_date
    INNER JOIN 
        dim_date AS dd_ds 
            ON rfb.sk_tenant_first_doc_sent_date = dd_ds.sk_date 
    INNER JOIN 
        dim_date AS dd_dc
            ON rfb.sk_tenant_doc_complete_date = dd_dc.sk_date
    INNER JOIN
        dim_date AS dd_da
            ON rfb.sk_credit_analysis_approved_date = dd_da.sk_date
    INNER JOIN 
        dim_date AS dd_guarantee
            ON rfb.sk_guarantee_paid_date = dd_guarantee.sk_date
    INNER JOIN 
        dim_date AS dd_cc
            ON rfb.sk_contract_created_date = dd_cc.sk_date
    INNER JOIN 
        dim_date AS dd_cs
            ON rfb.sk_contract_signed_date = dd_cs.sk_date
    ),
    
days_diff_and_cohorts_maturation AS (
    SELECT 
        sk_proposal,
        DATEDIFF('day',offer_submitted_date,offer_approved_date) AS days_offer_submitted_to_offer_approved,
        DATEDIFF('day',offer_approved_date,last_evaluation_started_date) AS days_offer_approved_to_evaluation_started,
        DATEDIFF('day',offer_approved_date,evaluation_approved_date) AS days_offer_approved_to_evaluation_approved,
        DATEDIFF('day',offer_approved_date,document_first_sent_date) AS days_offer_approved_to_document_first_sent,
        DATEDIFF('day',offer_approved_date,credit_analysis_approved_date) AS days_offer_approved_to_document_approved,
        DATEDIFF('day',offer_approved_date,contract_signed_date) AS days_offer_approved_to_contract_signed,
        DATEDIFF('day',last_evaluation_started_date,evaluation_approved_date) AS days_evaluation_started_to_evaluation_approved,
        DATEDIFF('day',last_evaluation_started_date,contract_signed_date) AS days_evaluation_started_to_contract_signed,
        DATEDIFF('day',evaluation_approved_date,document_first_sent_date) AS days_evaluation_approved_to_document_first_sent,
        DATEDIFF('day',document_first_sent_date,credit_analysis_approved_date) AS days_document_first_sent_to_document_approved,
        DATEDIFF('day',credit_analysis_approved_date,contract_signed_date) AS days_document_approved_to_contract_signed_date
    FROM 
        events_dates
    ),
    
pair_user_unique_proposal AS (
    SELECT
        rfb.sk_proposal,
        rfb.sk_offer_approved_date,
        rfb.sk_contract,
        rfb.sk_house_listing,
        rfb.sk_client,
        ed.offer_submitted_date,
        ed.offer_approved_date,
        ed.last_evaluation_started_date,
        ed.evaluation_approved_date,
        ed.document_first_sent_date,
        ed.document_completed_date,
        ed.credit_analysis_approved_date,
        ed.guarantee_paid_date,
        ed.contract_created_date,
        ed.contract_signed_date,
        fdf.flow_type,
        fdf.funnel_flow,
        ddcm.days_offer_submitted_to_offer_approved,
        ddcm.days_offer_approved_to_evaluation_started,
        ddcm.days_offer_approved_to_evaluation_approved,
        ddcm.days_offer_approved_to_document_first_sent,
        ddcm.days_offer_approved_to_document_approved,
        ddcm.days_offer_approved_to_contract_signed,
        ddcm.days_evaluation_started_to_evaluation_approved,
        ddcm.days_evaluation_started_to_contract_signed,
        ddcm.days_document_first_sent_to_document_approved,
        ddcm.days_document_approved_to_contract_signed_date,
        rfb.funnel_step,
        ROW_NUMBER() OVER(
            PARTITION BY 
                rfb.sk_client,
                date_trunc('week',ed.offer_approved_date)
    		ORDER BY 
    			rfb.sk_contract_signed_date DESC,
    			rfb.sk_credit_analysis_approved_date DESC,
    			rfb.sk_tenant_first_doc_sent_date DESC,
    			rfb.sk_last_credit_evaluation_positive DESC,
    			rfb.sk_last_credit_evaluation_init DESC,
    			rfb.sk_offer_approved_date DESC,
    			rfb.sk_offer_submitted_date DESC
    	) AS rn_user_month,
        COUNT(*) OVER(
            PARTITION BY 
                rfb.sk_client, 
                date_trunc('week',ed.offer_approved_date)
        ) AS offers_in_window
    FROM 
        rent_flows_base AS rfb
    INNER JOIN 
        events_dates AS ed
            ON rfb.sk_proposal = ed.sk_proposal
    INNER JOIN 
        days_diff_and_cohorts_maturation AS ddcm
            ON rfb.sk_proposal = ddcm.sk_proposal
    INNER JOIN 
        datamarts.funnel_demand_flows AS fdf 
            ON rfb.sk_rent_flow = fdf.sk_rent_flow
    )

SELECT 
    sk_proposal,
    sk_offer_approved_date,
    sk_contract,
    sk_house_listing,
    sk_client,
    offer_submitted_date,
    offer_approved_date,
    last_evaluation_started_date,
    evaluation_approved_date,
    document_first_sent_date,
    document_completed_date,
    credit_analysis_approved_date,
    guarantee_paid_date,
    contract_created_date,
    contract_signed_date,
    flow_type,
    funnel_flow,
    days_offer_submitted_to_offer_approved,
    days_offer_approved_to_evaluation_started,
    days_offer_approved_to_evaluation_approved,
    days_offer_approved_to_document_first_sent,
    days_offer_approved_to_document_approved,
    days_offer_approved_to_contract_signed,
    days_evaluation_started_to_evaluation_approved,
    days_evaluation_started_to_contract_signed,
    days_document_first_sent_to_document_approved,
    days_document_approved_to_contract_signed_date,
    funnel_step,
    offers_in_window
FROM 
    pair_user_unique_proposal
WHERE
    rn_user_month = 1
