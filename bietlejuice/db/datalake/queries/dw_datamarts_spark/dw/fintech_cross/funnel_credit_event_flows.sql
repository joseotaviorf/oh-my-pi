WITH max_contract AS (
    SELECT
        sk_proposal,
        MAX(sk_contract) max_sk_contract
    FROM
        dw_public.fact_listing_rent_flows
    GROUP BY 1
    ),

rent_flows_base AS (
    SELECT DISTINCT
        sk_rent_flow,
        sk_house_listing,
        sk_region,
        sk_client,
        sk_offer,
        f.sk_proposal,
        funnel_step,
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
        sk_contract_signed_date
    FROM
        dw_public.fact_listing_rent_flows f
    INNER JOIN
        dw_public.dim_date dd
            ON f.sk_offer_approved_date = dd.sk_date
    INNER JOIN
        max_contract mc
            ON f.sk_proposal = mc.sk_proposal
            AND f.sk_contract = mc.max_sk_contract
    WHERE
        dd.date >= '2020-01-01'
    ),
    
events_dates AS (
    SELECT
        rfb.sk_proposal,
        dd_os.date AS offer_submitted_date,
        dd_oa.date AS offer_approved_date,
        dd_es.date AS last_evaluation_started_date,
        COALESCE(dd_evp.date, CASE WHEN sk_last_credit_evaluation_positive < 0 AND sk_last_credit_evaluation_negative > 0 AND dp.guarantee = 'RentalGuarantee' THEN dd_evn.date END) AS evaluation_approved_date,
        dd_ds.date AS document_first_sent_date,
        dd_dc.date AS document_completed_date,
        dd_da.date AS last_document_approved_date,
        dd_guarantee.date AS guarantee_paid_date,
        dd_cc.date AS contract_created_date,
        dd_cs.date AS contract_signed_date
    FROM
        rent_flows_base AS rfb
    INNER JOIN
        dw_public.dim_proposal AS dp
            ON rfb.sk_proposal = dp.sk_proposal
    INNER JOIN
        dw_public.dim_date AS dd_os
            ON rfb.sk_offer_submitted_date = dd_os.sk_date
    INNER JOIN
        dw_public.dim_date AS dd_oa
            ON rfb.sk_offer_approved_date = dd_oa.sk_date
    INNER JOIN
        dw_public.dim_date AS dd_es
            ON rfb.sk_last_credit_evaluation_init = dd_es.sk_date
    INNER JOIN
        dw_public.dim_date AS dd_evp
            ON rfb.sk_last_credit_evaluation_positive = dd_evp.sk_date
    INNER JOIN
        dw_public.dim_date AS dd_evn
            ON rfb.sk_last_credit_evaluation_negative = dd_evn.sk_date
    INNER JOIN
        dw_public.dim_date AS dd_ds 
            ON rfb.sk_tenant_first_doc_sent_date = dd_ds.sk_date 
    INNER JOIN
        dw_public.dim_date AS dd_dc
            ON rfb.sk_tenant_doc_complete_date = dd_dc.sk_date
    INNER JOIN
        dw_public.dim_date AS dd_da
            ON rfb.sk_credit_analysis_approved_date = dd_da.sk_date
    INNER JOIN
        dw_public.dim_date AS dd_guarantee
            ON rfb.sk_guarantee_paid_date = dd_guarantee.sk_date
    INNER JOIN
        dw_public.dim_date AS dd_cc
            ON rfb.sk_contract_created_date = dd_cc.sk_date
    INNER JOIN
        dw_public.dim_date AS dd_cs
            ON rfb.sk_contract_signed_date = dd_cs.sk_date
    ),
    
days_diff_and_cohorts_maturation AS (
    SELECT
        sk_proposal,
        DATEDIFF(offer_submitted_date,offer_approved_date) AS days_offer_submitted_to_offer_approved,
        DATEDIFF(offer_approved_date,last_evaluation_started_date) AS days_offer_approved_to_evaluation_started,
        DATEDIFF(offer_approved_date,evaluation_approved_date) AS days_offer_approved_to_evaluation_approved,
        DATEDIFF(offer_approved_date,document_first_sent_date) AS days_offer_approved_to_document_first_sent,
        DATEDIFF(offer_approved_date,last_document_approved_date) AS days_offer_approved_to_document_approved,
        DATEDIFF(offer_approved_date,contract_signed_date) AS days_offer_approved_to_contract_signed,
        DATEDIFF(last_evaluation_started_date,evaluation_approved_date) AS days_evaluation_started_to_evaluation_approved,
        DATEDIFF(last_evaluation_started_date,contract_signed_date) AS days_evaluation_started_to_contract_signed,
        DATEDIFF(evaluation_approved_date,document_first_sent_date) AS days_evaluation_approved_to_document_first_sent,
        DATEDIFF(document_first_sent_date,last_document_approved_date) AS days_document_first_sent_to_document_approved,
        DATEDIFF(last_document_approved_date,contract_signed_date) AS days_document_approved_to_contract_signed
    FROM
        events_dates
    )
    
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
    ed.last_document_approved_date,
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
    ddcm.days_document_approved_to_contract_signed,
    rfb.funnel_step
FROM
    rent_flows_base AS rfb
INNER JOIN
    events_dates AS ed
        ON rfb.sk_proposal = ed.sk_proposal
INNER JOIN
    days_diff_and_cohorts_maturation AS ddcm
        ON rfb.sk_proposal = ddcm.sk_proposal
INNER JOIN
    dw_datamarts_cross.funnel_demand_flows AS fdf 
        ON rfb.sk_rent_flow = fdf.sk_rent_flow
