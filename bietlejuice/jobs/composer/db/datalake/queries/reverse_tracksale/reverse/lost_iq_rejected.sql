WITH distinct_offers AS (
    SELECT 
        rf.sk_client, 
        rf.sk_offer,
        rf.sk_proposal,
        rf.sk_offer_submitted_date,
        rf.sk_offer_approved_date
    FROM dw_public.fact_listing_rent_flows rf
    WHERE sk_offer > 0
    GROUP BY 1,2,3,4,5
),
first_offer AS (
    SELECT 
        sk_client,
        min(sk_offer) AS first_sk_offer 
    FROM distinct_offers
    GROUP BY 1
),
next_offers AS (
    SELECT 
        od.sk_client,
        od.sk_offer,
        od.sk_offer_submitted_date,
        od.sk_offer_approved_date,
        dof.rejection_reason AS offer_rejection_reason,
        dp.rejection_reason AS proposal_rejection_reason,
        dp.result_credit_evaluation AS proposal_result_credit_evaluation,
        lead(od.sk_offer,1) over (PARTITION by od.sk_client ORDER BY od.sk_offer) AS next_sk_offer 
    FROM distinct_offers od
    INNER JOIN dw_public.dim_offer dof 
        ON dof.sk_offer = od.sk_offer
    LEFT JOIN dw_public.dim_proposal dp 
        ON dp.sk_proposal = od.sk_proposal 
 ),
first_offer_city AS (
    SELECT 
        no.*
    FROM next_offers no
    INNER JOIN first_offer fo 
        ON no.sk_offer = fo.first_sk_offer
),
distinct_bookings AS (
    SELECT 
        rf.sk_client,
        rf.sk_booking,
        rf.sk_booking_created_date
    FROM dw_public.fact_listing_rent_flows rf
    INNER JOIN dw_public.dim_region dr 
        ON dr.sk_region = rf.sk_region  
    WHERE rf.sk_booking_created_date > 0
    GROUP BY 1,2,3
),
distinct_documentations AS (
    SELECT 
        sk_client,
        sk_tenant_first_doc_sent_date
    FROM dw_public.fact_listing_rent_flows    
    WHERE sk_tenant_first_doc_sent_date > 0
    GROUP BY 1,2
),
distinct_contracts AS (
    SELECT 
        sk_client,
        sk_contract,
        sk_contract_signed_date
    FROM dw_public.fact_listing_rent_flows    
    WHERE sk_contract_signed_date > 0
    GROUP BY 1,2,3
),
active_contracts AS (
    SELECT 
        rf.sk_client,
        COUNT(rf.sk_contract) > 0 AS has_active_contracts
    FROM dw_public.fact_listing_rent_flows rf
    INNER JOIN dw_public.dim_contract dc 
        ON rf.sk_contract = dc.sk_contract 
    WHERE rf.sk_contract_signed_date >0
        AND dc.status = 'Ativo'
    GROUP BY 1
),
positive_credit_evaluations AS (
    SELECT 
        id_user,
        id_proposal,
        cast(replace(substring(cast(ts_updated AS STRING),1,10),'-','') AS INTEGER) AS sk_updated_date
    FROM datalake_docx_clean.credit_evaluation ce
    WHERE status = 'FINISHED'
        AND result = 'PRE_APPROVED'
),
next_steps AS (
    SELECT 
        fo.sk_client,
        fo.sk_offer,
        dt.date AS dt_offer,
        fo.sk_offer_approved_date,
        fo.offer_rejection_reason,
        fo.proposal_rejection_reason,
        fo.proposal_result_credit_evaluation,
        fo.next_sk_offer,
        db.sk_booking AS next_sk_booking,
        dd.sk_tenant_first_doc_sent_date AS next_doc_sent,
        dc.sk_contract AS next_sk_contract,
        coalesce(ac.has_active_contracts,false) AS has_active_contracts,
        pce.id_proposal AS positive_credit_evaluation 
    FROM first_offer_city fo
    INNER JOIN dw_public.dim_date dt 
        ON dt.sk_date = fo.sk_offer_submitted_date
    LEFT JOIN distinct_bookings db 
        ON db.sk_client = fo.sk_client
        AND db.sk_booking_created_date >= fo.sk_offer_submitted_date 
    LEFT JOIN distinct_documentations dd 
        ON dd.sk_client = fo.sk_client
        AND dd.sk_tenant_first_doc_sent_date >= fo.sk_offer_submitted_date 
    LEFT JOIN distinct_contracts dc 
        ON dc.sk_client = fo.sk_client
        AND dc.sk_contract_signed_date >= fo.sk_offer_submitted_date
    LEFT JOIN active_contracts ac 
        ON ac.sk_client = fo.sk_client
    LEFT JOIN positive_credit_evaluations pce 
        ON pce.id_user = fo.sk_client
        AND pce.sk_updated_date >= fo.sk_offer_submitted_date
),
proponents_rejected AS (
    SELECT 
        sk_client,
        sk_offer,
        'Negociação' AS step
    FROM next_steps 
    WHERE 
        dt_offer = date_add(-10,current_date) 
        AND NOT sk_offer_approved_date > 0 
        AND next_sk_offer IS NULL 
        AND next_sk_booking IS NULL 
        AND has_active_contracts = false
        AND positive_credit_evaluation IS NULL 
    GROUP BY 1,2,3  
),
proponents_approved_docs AS (
    SELECT 
        sk_client,
        sk_offer,
        'Negociação' AS step,
        proposal_rejection_reason,
        proposal_result_credit_evaluation
    FROM next_steps 
    WHERE 
        dt_offer = date_add(current_date, -10) 
        AND sk_offer_approved_date > 0 
        AND next_doc_sent IS NULL 
        AND has_active_contracts = false
        AND positive_credit_evaluation IS NULL 
    GROUP BY 1,2,3,4,5   
),
proponents_approved_docs_rejected AS (
	SELECT DISTINCT 
        sk_client
	FROM proponents_approved_docs
	WHERE proposal_result_credit_evaluation = 'PRE_REJECTED'
	    OR proposal_rejection_reason IN ('CreditEvaluationRejected','TenantDocumentationRejected')
),
proponents_approved_docs_correct AS (
	SELECT 
		p.sk_client,
		p.sk_offer,
		p.step
	FROM proponents_approved_docs p
	WHERE p.sk_client IN (SELECT * FROM proponents_approved_docs_rejected)
),
proponents_approved_contract AS (
    SELECT 
        sk_client,
        sk_offer,
        'Contrato' AS step,
        proposal_result_credit_evaluation,
        proposal_rejection_reason
    FROM next_steps 
    WHERE 
        dt_offer = date_add(current_date, -10) 
        AND sk_offer_approved_date > 0 
        AND next_doc_sent > 0  
        AND next_sk_contract IS NULL 
        AND positive_credit_evaluation IS NULL 
    GROUP BY 1,2,3,4,5
),
proponents_approved_contract_rejected AS (
	SELECT DISTINCT 
        sk_client
	FROM proponents_approved_contract
	WHERE proposal_result_credit_evaluation = 'PRE_REJECTED'
	OR proposal_rejection_reason IN ('CreditEvaluationRejected','TenantDocumentationRejected')
),
proponents_approved_contract_correct AS (
	SELECT 
		p.sk_client,
		p.sk_offer,
		p.step
	FROM proponents_approved_contract p
	WHERE p.sk_client IN (SELECT * FROM proponents_approved_contract_rejected)
),
dispatches AS (
    SELECT * FROM proponents_approved_docs_correct
    UNION 
    SELECT * FROM proponents_approved_contract_correct
),
crisis_users AS (
    SELECT 
        ft.sk_user
    FROM dw_tickets.dim_ticket dt
    INNER JOIN dw_tickets.fact_tickets ft 
        ON dt.sk_ticket  = ft.sk_ticket
    INNER JOIN datalake_gsheets_clean.department_control dc 
        ON dt.group_name = dc.department
    WHERE dc.team in ('Casos Especiais','Proteção 5A','Ouvidoria','ReclameAqui') 
        AND ft.sk_closed_date_local = -1 
    GROUP BY 1
),
proponents AS (
    SELECT
        sk_client,
        sk_offer,
        MIN(step) AS step 
    FROM dispatches d
    LEFT JOIN crisis_users uc 
        ON uc.sk_user = d.sk_client
        AND uc.sk_user IS NULL 
    GROUP BY 1,2
)
SELECT
    u.nome AS customer_name,
    u.email AS customer_email,
    u.telefone_principal AS customer_phone,
    p.step AS campaign_step,
    'Inquilino' AS customer_type,
    u.cpf AS customer_cpf,
    u.sk_user AS id_user,
    'lost' AS campaign_type,
    'offer' AS driver_type,
    p.sk_offer AS id_driver,
    NOW() AS ts_load
FROM proponents p 
INNER JOIN dw_public.dim_user u 
    ON u.sk_user = p.sk_client
UNION ALL 
SELECT
    'Teste Disparo' AS customer_name,
    'testes.disparos.5a@gmail.com' AS customer_email,
    '+5511123456789' AS customer_phone,
    'Negociação' AS campaign_step,
    'Inquilino' AS customer_type,
    '1234' AS customer_cpf,
    '1234' AS id_user,
    'lost' AS campaign_type,
    'offer' AS driver_type,
    '1234' AS id_driver,
    NOW() AS ts_load