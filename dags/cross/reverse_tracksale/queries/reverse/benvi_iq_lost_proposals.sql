-- Benvi IQ Lost Proposals:
-- 1) proponents with offers sent on D-10 and rejected not by credit who did neither send another offer not book a visit after that
-- 2) proponents with offers sent on D-10 and approved who did not send documentation after that
-- 3) proponents with documentation sent on D-10 for credit analysis who did not sign a contract after that, by any reason except documentation rejected
WITH mexico_houses AS (
    SELECT
        DISTINCT sk_house_listing
    FROM
        dw_public.dim_house_listing
    WHERE
        country_code = 'MX' --- added to filter only MX business (excluding BR)
),
distinct_offers AS (
    SELECT
        rf.sk_client,
        rf.sk_offer,
        rf.sk_proposal,
        rf.sk_offer_submitted_date,
        rf.sk_offer_approved_date
    FROM
        dw_public.fact_listing_rent_flows AS rf
    INNER JOIN
        mexico_houses AS h
            ON rf.sk_house_listing=h.sk_house_listing  --- added to filter only BR business (excluding mexico)
            AND rf.sk_offer > 0
    GROUP BY 1, 2, 3, 4, 5
),
-- consider the first offer on D-10 for each proponent
first_offer AS (
    SELECT
        sk_client,
        MIN(sk_offer) AS first_sk_offer -- id because there could be n offers in a day
    FROM
        distinct_offers
    GROUP BY 1
),
-- relate next offer for each proponent
next_offers AS (
    SELECT
        od.sk_client,
        od.sk_offer,
        od.sk_offer_submitted_date,
        od.sk_offer_approved_date,
        dof.rejection_reason AS offer_rejection_reason,
        dp.rejection_reason AS proposal_rejection_reason,
        dp.result_credit_evaluation AS proposal_result_credit_evaluation,
        LEAD(od.sk_offer, 1) OVER (PARTITION BY od.sk_client ORDER BY od.sk_offer) AS next_sk_offer -- next offer will have a greater id (incremental)
    FROM
        distinct_offers AS od
    INNER JOIN
        dw_public.dim_offer AS dof
            ON dof.sk_offer = od.sk_offer
            AND dof.country_code = 'MX'
    LEFT JOIN
        dw_rent.dim_proposal AS dp
            ON dp.sk_proposal = od.sk_proposal
),
-- consider only the city of the first offer for each proponent
first_offer_city AS (
    SELECT
        no.*
    FROM
        next_offers AS no
    INNER JOIN
        first_offer AS fo
            ON no.sk_offer = fo.first_sk_offer
),
-- get all distinct bookings for each client
distinct_bookings as (
    SELECT
        rf.sk_client,
        rf.sk_booking,
        rf.sk_booking_created_date
    FROM
        dw_public.fact_listing_rent_flows AS rf
    INNER JOIN
        dw_public.dim_region AS dr
            ON dr.sk_region = rf.sk_region
            AND dr.country_code = 'MX'
            AND rf.sk_booking_created_date > 0
    GROUP BY 1, 2, 3
),
-- get all distinct documentations sent by each client
distinct_documentations AS (
    SELECT
        sk_client,
        sk_tenant_first_doc_sent_date
    FROM
        dw_public.fact_listing_rent_flows
    WHERE
        sk_tenant_first_doc_sent_date > 0
    GROUP BY 1, 2
),
-- get all distinct contracts signed FROM each client
distinct_contracts AS (
    SELECT
        sk_client,
        sk_contract,
        sk_contract_signed_date
    FROM
        dw_public.fact_listing_rent_flows
    WHERE
        sk_contract_signed_date > 0
    GROUP BY 1, 2, 3
),
active_contracts as (
    SELECT
        rf.sk_client,
        COUNT(rf.sk_contract) > 0 AS has_active_contracts
    FROM
        dw_public.fact_listing_rent_flows AS rf
    INNER JOIN
        dw_public.dim_contract AS dc
            ON rf.sk_contract = dc.sk_contract
            AND dc.country_code = 'MX'
            AND rf.sk_contract_signed_date > 0
            AND dc.status = 'Ativo'
    GROUP BY 1
),
positive_credit_evaluations as (
    SELECT
        id_user,
        id_proposal,
        CAST(REPLACE(SUBSTRING(CAST(ts_updated AS STRING), 1, 10), '-', '') AS INTEGER) AS sk_updated_date
    FROM
        datalake_docx_clean.credit_evaluation AS ce
    WHERE
        status = 'FINISHED'
        AND result = 'PRE_APPROVED'
),
-- relate next funnel steps (offer or booking) for each client
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
    FROM
        first_offer_city AS fo
    INNER JOIN
        dw_public.dim_date AS dt
            ON dt.sk_date = fo.sk_offer_submitted_date
    LEFT JOIN
        distinct_bookings AS db
            ON db.sk_client = fo.sk_client
            AND db.sk_booking_created_date >= fo.sk_offer_submitted_date
    LEFT JOIN
        distinct_documentations AS dd
            ON dd.sk_client = fo.sk_client
            AND dd.sk_tenant_first_doc_sent_date >= fo.sk_offer_submitted_date
    LEFT JOIN
        distinct_contracts AS dc
            ON dc.sk_client = fo.sk_client
            AND dc.sk_contract_signed_date >= fo.sk_offer_submitted_date
    LEFT JOIN
        active_contracts AS ac
            ON ac.sk_client = fo.sk_client
    LEFT JOIN
        positive_credit_evaluations AS pce
            ON pce.id_user = fo.sk_client
            AND pce.sk_updated_date >= fo.sk_offer_submitted_date
),
-- filter clients with offer rejected and no further booking/offer
proponents_rejected AS (
    SELECT
        sk_client,
        sk_offer,
        'Negociação' AS step
    FROM
        next_steps
    WHERE
        dt_offer = DATE_ADD(CURRENT_DATE(), -10) -- SELECT the initial offer on D-10
        AND NOT sk_offer_approved_date > 0 -- selecting offers that were not approved (all might have a line with -1)
        AND next_sk_offer IS NULL -- selecting offers without a next offer
        AND next_sk_booking IS NULL -- selecting offers without a next booking
        AND has_active_contracts IS FALSE -- excluding clients with active contracts
        AND positive_credit_evaluation IS NULL -- excluding clients with a later positive credit evaluation
    GROUP BY 1, 2, 3
),
-- filter clients with offer approved and no further documentation sent
proponents_approved_docs AS (
    SELECT
        sk_client,
        sk_offer,
        'Negociação' AS step,
        proposal_rejection_reason,
        proposal_result_credit_evaluation
    FROM
        next_steps
    WHERE
        dt_offer = DATE_ADD(CURRENT_DATE(), -10) -- SELECT the initial offer on D-10
        AND sk_offer_approved_date > 0 -- selecting offers that were approved
        AND next_doc_sent IS NULL -- selecting proponents that did not send docs
        AND has_active_contracts IS FALSE -- excluding clients with active contracts
        AND positive_credit_evaluation IS NULL -- excluding clients with a later positive credit evaluation
    GROUP BY 1, 2, 3, 4, 5
),
proponents_approved_docs_rejected AS (
    SELECT
        DISTINCT sk_client
    FROM
        proponents_approved_docs
    WHERE
        proposal_result_credit_evaluation = 'PRE_REJECTED'
        OR proposal_rejection_reason IN ('CreditEvaluationRejected','TenantDocumentationRejected')
),
proponents_approved_docs_correct as (
    SELECT
        sk_client,
        sk_offer,
        step
    FROM
        proponents_approved_docs
    WHERE
        sk_client NOT IN (SELECT * FROM proponents_approved_docs_rejected)
),
-- filter clients with offer approved and no further contract signed
proponents_approved_contract AS (
    SELECT
        sk_client,
        sk_offer,
        'Contrato' AS step,
        proposal_result_credit_evaluation,
        proposal_rejection_reason
    FROM
        next_steps
    WHERE
        dt_offer = DATE_ADD(CURRENT_DATE(), -10) -- SELECT the initial offer on D-10
        AND sk_offer_approved_date > 0 -- selecting offers that were approved
        AND next_doc_sent > 0  -- selecting offers that did not send docs
        AND next_sk_contract IS NULL -- selecting proponents that did not sign contracts
        AND positive_credit_evaluation IS NULL -- excluding clients with a later positive credit evaluation
    GROUP BY 1, 2, 3, 4, 5
),
proponents_approved_contract_rejected AS (
    SELECT
        DISTINCT sk_client
    FROM
        proponents_approved_contract
    WHERE
        proposal_result_credit_evaluation = 'PRE_REJECTED'
        OR proposal_rejection_reason IN ('CreditEvaluationRejected','TenantDocumentationRejected')
),
proponents_approved_contract_correct AS (
    SELECT
        sk_client,
        sk_offer,
        step
    FROM
        proponents_approved_contract
    WHERE
        sk_client NOT IN (SELECT * FROM proponents_approved_contract_rejected)
),
-- filter proponents with NPS conditions
dispatches AS (
    SELECT
        *
    FROM
        proponents_rejected
    UNION
    SELECT
        *
    FROM
        proponents_approved_docs_correct
    UNION
    SELECT
        *
    FROM
        proponents_approved_contract_correct
),
-- avoid users which experience ongoing crisis, there is crisis tickets not closed yet
crisis_users AS (
    SELECT
        ft.sk_user
    FROM
        dw_tickets.dim_ticket AS dt
    INNER JOIN
        dw_tickets.fact_tickets AS ft
            ON dt.sk_ticket  = ft.sk_ticket
            AND ft.sk_closed_date_local = -1
    INNER JOIN
        dw_customer_support.dim_department AS dc
            ON dt.group_name = dc.department
			AND dc.team IN ('Casos Especiais','Proteção 5A','Ouvidoria','ReclameAqui') -- exclude contracts from these areas
    GROUP BY 1
),
-- select each client only once if s/he has been in both steps (contract and negotiation)
proponents AS (
    SELECT
        sk_client,
        sk_offer,
        MIN(step) AS step -- if both, select contract, that is the last step
    FROM
        dispatches AS d
    LEFT JOIN
        crisis_users AS uc
            ON uc.sk_user = d.sk_client
            AND uc.sk_user IS NULL -- exclude users with ongoing crisis ticket
    GROUP BY 1, 2
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
FROM
    proponents AS p
INNER JOIN
    dw_public.dim_user AS u
        ON u.sk_user = p.sk_client
UNION ALL
SELECT
    'Teste Disparo' AS customer_name,
    'testes.disparos.5a@gmail.com' AS customer_email,
    '+5511123456789' AS customer_phone,
    'Negociação' AS campaign_step,
    'Inquilino' AS customer_type,
    '1234' AS customer_cpf,
    '1224' AS id_user,
    'lost' AS campaign_type,
    'offer' AS driver_type,
    '1234' AS id_driver,
    NOW() AS ts_load
