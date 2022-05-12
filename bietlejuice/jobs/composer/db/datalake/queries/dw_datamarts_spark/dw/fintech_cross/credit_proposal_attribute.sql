WITH rent_flows_base AS (
    SELECT
        sk_house_listing,
        LEFT(sk_house_listing,9) AS id_house,
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
        sk_last_doc_analysis_approved,
        sk_guarantee_paid_date,
        sk_contract_created_date,
        sk_contract_signed_date
    FROM 
        dw_public.fact_listing_rent_flows f
    INNER JOIN dw_public.dim_date dd
        ON f.sk_offer_approved_date = dd.sk_date
    WHERE
        dd.date >= '2020-01-01'
    ),

tenants AS (
    SELECT
        id_proposal,
        COUNT(*) AS tenants,
        SUM(CASE WHEN will_live is true THEN 1 ELSE 0 END) AS solidarity_tenant
    FROM
        datalake_ebdb_clean.proponent_proposal pp
    WHERE
        type = 'Inquilino'
        AND ts_created >= '2020-01-01'
    GROUP BY 1
    ),

proponent AS (
    SELECT
        id,
        id_proposal,
        id_screening_result,
        is_going_to_reside,
        boavista_score,
        serasa_score,
        monthly_income,
        income_nature
    FROM
        datalake_sorting_hat_clean.proponent
    ),

user_proposal_score AS (
    SELECT
        id_proposal,
        MAX(boavista_score) AS bv_score,
        MAX(serasa_score) AS serasa_score
    FROM 
        proponent
    WHERE
        id_screening_result IS NOT NULL
    GROUP BY 1
    ),
    
dti AS (
    SELECT
        p.id,
        MAX(p.status) AS status,
        MAX(p.ts_created) AS created_at,
        SUM(p2.monthly_income) AS income,
        MAX(p.rent_value + p.condo_value + p.iptu_value + NULLIF(p.home_insurance_value,0)) AS package
    FROM 
        datalake_sorting_hat_clean.proposal AS p
    LEFT JOIN 
        proponent AS p2
            ON p.id = p2.id_proposal 
    WHERE
        p.ts_created >= '2020-01-01'
    GROUP BY 1
    ),
    
job_type AS (
    with proposal_income_nature AS (
        SELECT
            id_proposal,
            SUM(CASE WHEN income_nature = 'CLT' THEN 1 ELSE 0 END) AS clt,
            SUM(CASE WHEN income_nature != 'CLT' THEN 1 ELSE 0 END) AS outros,
            COUNT(DISTINCT id) AS total_iq
	FROM 
	    proponent
	GROUP BY 1
    )
    
    SELECT
        DISTINCT id_proposal,
        CASE
            WHEN clt = total_iq THEN 'clt'
            WHEN outros = total_iq THEN 'outros'
            WHEN clt > 0 THEN 'clt'
            WHEN outros > 0 THEN 'outros'
            ELSE ''
        END AS jobtype
    FROM 
        proposal_income_nature
    ),
    
credit_analysis AS (
    with last_status AS (
    	SELECT
    	    id_proposal,
    	    max(ts_updated) AS laststatus
        FROM datalake_sorting_hat_clean.credit_analysis
        WHERE
            ts_created >= '2020-01-01'
        GROUP BY 1
	) 
	    
	SELECT
	    ca.id_proposal,
	    ca.category,
	    ca.type,
	    ca.level,
	    ca.result,
	    ca.reason,
	    ca.id_analyst,
	    ca.analyst_name,
	    ca.automatic_decision_reason,
	    ca.bypass,
	    ca.is_a_potential_interview
	FROM datalake_sorting_hat_clean.credit_analysis AS ca
	INNER JOIN 
	    last_status AS ls
	        ON ls.id_proposal = ca.id_proposal AND ls.laststatus = ca.ts_updated
	WHERE
        ca.ts_created >= '2020-01-01'
	),
	
house_origin_type as (
    SELECT
        dhl.id_house,
        CASE
            WHEN ciq.is_ciq_origin = true THEN ciq.type_big_agent
            WHEN ciq.is_ciq_origin = false THEN ciq.type_big_agent
            WHEN dhl.is_b2b = true THEN 'B2B'
            ELSE 'Core'
        END as house_origin_type
    FROM dw_public.dim_house_listing AS dhl
    LEFT JOIN
        dw_datamarts_cross.quintoandar_consultant_listings AS ciq
            ON dhl.id_house = ciq.id_house
    WHERE
        dhl.ts_house_first_publication >= '2020-01-01'
    )
    
SELECT DISTINCT
    rfb.sk_proposal,
    dp.status AS status_proposal,
    dp.status_sortinghat AS status_sortinghat,
    dp.status_doc_tenant AS status_doc_tenant,
    dp.rejection_reason AS proposal_rejection_reason,
    dp.guarantee AS proposal_guarantee,
    dc.cancellation_reason AS contract_cancellation_reason,
    jt.jobtype,
    dti.income,
    dti.package,
    (dti.package / NULLIF(CAST(dti.income AS DOUBLE), 0.0)) AS dti,
    ca.type,
    ca.level,
    ca.result,
    ca.reason,
    ca.id_analyst,
    ca.analyst_name,
    ca.automatic_decision_reason,
    ca.bypass,
    ca.is_a_potential_interview,
    ca.category,
    CASE
        WHEN ca.category = 0 THEN 'Gratis'
        WHEN ca.category IN (1,2,3,4,5,6) THEN 'Garantia'
        WHEN ca.category IS NULL THEN 'Clear No'
        ELSE 'Outros'
    END AS classification,
    t.tenants,
    t.solidarity_tenant,
    dr.city_group,
    dr.city_name,
    ups.bv_score,
    ups.serasa_score,    
    sr.risk_category,
    sr.score,
    CASE 
        WHEN sr.score between 0 AND 350 THEN 'E'
        WHEN sr.score between 351 AND 569 THEN 'D'
        WHEN sr.score between 570 AND 815 THEN 'C'
        WHEN sr.score between 816 AND 913 THEN 'B'
        WHEN sr.score between 914 AND 1000 THEN 'A'
    END AS fx_score_5a,
    dof.is_instant_offer,
    dof.type AS offer_type,
    ht.house_origin_type
FROM
    rent_flows_base AS rfb
INNER JOIN
    dw_public.dim_proposal AS dp
        ON rfb.sk_proposal = dp.sk_proposal
LEFT JOIN
    house_origin_type AS ht
        ON rfb.id_house = ht.id_house
LEFT JOIN
    dw_public.dim_contract AS dc
        ON rfb.sk_contract = dc.sk_contract
INNER JOIN 
    dw_public.dim_offer AS dof
        ON rfb.sk_offer = dof.sk_offer
LEFT JOIN
    datalake_sorting_hat_clean.screening_result AS sr
        ON rfb.sk_proposal = sr.id_proposal
LEFT JOIN
    user_proposal_score AS ups
        ON rfb.sk_proposal = ups.id_proposal
INNER JOIN 
    dw_public.dim_region AS dr
        ON rfb.sk_region = dr.sk_region
LEFT JOIN
    dti
        ON rfb.sk_proposal = dti.id
LEFT JOIN
    job_type AS jt
        ON rfb.sk_proposal = jt.id_proposal
LEFT JOIN
    credit_analysis AS ca
        ON rfb.sk_proposal = ca.id_proposal
LEFT JOIN
    tenants AS t
        ON rfb.sk_proposal = t.id_proposal