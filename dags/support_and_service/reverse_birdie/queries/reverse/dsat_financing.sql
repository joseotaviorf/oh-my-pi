-- CTE de dados de usuários (comprador e vendedor)
WITH dim_user_sale AS (
    SELECT 
        fo.sk_offer, 
        fo.sk_house,
        fo.sk_buyer,
        REPLACE(du.telefone_principal, '+','') AS phone_buyer,
        du.email AS email_buyer, 
        du.nome AS name_buyer, 
        fo.sk_owner AS sk_seller,
        REPLACE(sl.telefone_principal, '+','') AS phone_seller,
        sl.email AS email_seller, 
        sl.nome AS name_seller
    FROM dw_sale.fact_offers fo
    LEFT JOIN dw_public.dim_user du ON fo.sk_buyer = du.sk_user 
    LEFT JOIN dw_public.dim_user sl ON fo.sk_owner = sl.sk_user 
),

-- CTE com bandeira de vendedores internos
base_offers_internal_vendors AS (
    SELECT
        sk_offer,
        CASE 
            WHEN payment_method IN ('FINANCED_USING_FGTS', 'FINANCED') AND credit_model IN ('UNDEFINED','ATTA') THEN TRUE
            WHEN payment_method IN ('FINANCED_USING_FGTS', 'FINANCED') AND credit_model = 'EXTERNAL' THEN FALSE
        END AS internal_vendors_flag
    FROM dw_sale.dim_offer
),

-- CTE com dados principais da oferta
offer AS (
    SELECT 
        fo.sk_offer,
        DATE(dsa.ts_sale_agreement_signed) AS ts_sale_agreement_signed,
        fo.sk_buyer,
        fo.sk_owner,
        financing_bank,
        payment_method,
        dsa.credit_model,
        dsa.closing_status,
        dsa.house_dilligence_status,
        dsa.seller_dilligence_status,
        dsa.report_dilligence_status,
        dsa.bank_analysis_status,
        dsa.payment_status,
        dsa.credit_status,
        dsa.has_used_fgts_in_payment,
        dsa.has_seller_debt_payments,
        fo.last_price_offered_by_buyer AS sale_price,
        dsa.is_3p_supply,
        dsa.is_3p_demand,
        dsa.payment_model,
        dsa.ts_house_registry_ended,
        dim.city_group,
        duser.email AS email_especialist,
        dsa.ccv_model,
        dsa.is_ccv_canceled
    FROM dw_sale.fact_offers fo
    JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer 
    LEFT JOIN dw_public.dim_region dim ON fo.sk_region = dim.sk_region
    LEFT JOIN dw_public.dim_user duser ON fo.sk_user_consultant = duser.id
),

-- CTE de tickets filtrados com QUALIFY
tickets AS (
    SELECT
        em.id_ticket,
        em.id_user,
        an.email,
        ts_ticket_ended,
        ts_sla_started,
        ts_closed,
        CASE 
            WHEN an.email LIKE '%webhelpbr.com.br' THEN 'webhelp'
            WHEN an.email LIKE '%quintoandar.com.br' THEN 'quintoandar'
            ELSE NULL
        END AS agent_company,
        tkt.sk_sale_offer AS offer_id,
        tkt.sk_last_analyst,
        tkt.channel,
        ROW_NUMBER() OVER (PARTITION BY em.id_user ORDER BY ts_sla_started DESC) AS rn
    FROM datalake_customer_support.email em
    LEFT JOIN dw_customer_support.fact_tickets tkt ON CAST(em.id_ticket AS BIGINT) = tkt.sk_ticket
    LEFT JOIN dw_customer_support.dim_ticket tkt2 ON tkt2.sk_ticket = tkt.sk_ticket
    LEFT JOIN dw_customer_support.dim_department de ON de.sk_department = tkt.sk_main_department
    LEFT JOIN dw_customer_support.dim_analyst an ON tkt.sk_last_analyst = an.sk_analyst
    WHERE 
        tkt.channel = 'email' AND 
        tkt2.status IN ('closed', 'solved') AND 
        de.department IN (
            'WH - Financiamento Interno [SALE] [POS] FRONT]',
            'À Vista NM [SALE] [POS] [FRONT]',
            'Atendimento Reativo [SALE] [POS] [FRONT]',
            'Financiamento Externo [SALE] [POS] [FRONT]',
            'Financiamento Interno [SALE] [POS] [FRONT]',
            'Especialista N2 [SALE] [POS] [BACK]',
            'CRI Financiamento Interno [SALE] [POS] [FRONT]',
            'WH - À Vista [SALE] [POS] [FRONT]',
            'WH - Financiamento Externo [SALE] [POS] [FRONT]',
            'Closing Lab [RC]',
            'Incubadora-Front [EoP] [Forsale]',
            'WH - Híbridos [SALE] [POS] [FRONT]',
            'WH - Consórcio [SALE][POS][FRONT]'
        )
    QUALIFY rn = 1
),

-- CTE especialista do pós com ticket mais recente
post_specialist AS (
    SELECT DISTINCT
        sk_offer,
        id_user,
        email
    FROM offer
    LEFT JOIN tickets ON offer_id = sk_offer AND id_user = sk_buyer
),

-- CTE com dados do fluxo de fechamento
fact_closing_flows AS (
    SELECT
        fcf.sk_offer,
        dsa.payment_method,
        dsa.credit_model,
        dsa.financing_bank,
        dr.city_group,
        fos.legal_risk_analyst_email
    FROM dw_sale.fact_closing_flows fcf
    LEFT JOIN dw_sale.dim_sale_agreement dsa ON fcf.sk_offer = dsa.sk_offer
    LEFT JOIN dw_sale.fact_offers fo ON fcf.sk_offer = fo.sk_offer
    LEFT JOIN dw_public.dim_region dr ON fo.sk_region = dr.sk_region
    LEFT JOIN datalake_sale_offer_flows.offer_specialists fos ON fos.id_offer = fcf.sk_offer
    WHERE 
        dsa.payment_model = 'CCV_ASSISTANCE' AND 
        dsa.is_ccv_canceled = false AND 
        dsa.ccv_model != 'Not a 5A model'
),

-- CTE com última análise da franquia
franchise_last_pre_analysis AS (
    SELECT 
        sk_offer,
        franchise_name
    FROM dw_atta.fact_pre_analysis_proposal_flow fpp
    LEFT JOIN dw_atta.dim_franchise_atta dfr ON fpp.sk_franchise = dfr.sk_franchise
    QUALIFY ROW_NUMBER() OVER(PARTITION BY sk_offer ORDER BY ts_last_updated DESC) = 1
),

-- CTE com telefone vinculado a notificações
tel_user AS (
    SELECT 
        n.destination AS tel,
        n.id_user
    FROM datalake_jaiminho_clean.user_notifications n
    WHERE entity_name = 'postAcceptedDiligenceThermometerSurvey'
),

-- CTE NPS com rating e motivos
nps AS (
    SELECT 
        'Financiamento' AS nome_campanha,
        rc.id_response AS feedback_id,
        rc.ts_collected AS posted_at,
        PARSE_URL(sr.response_url, 'QUERY', 'offer') AS offer_id,
        PARSE_URL(sr.response_url, 'QUERY', 'tel') AS phone,
        MAX(CASE WHEN rc.id_question = '2718007' THEN rc.answer_content END) AS satisfaction_raw,
        ARRAY_JOIN(ARRAY_AGG(DISTINCT rc.answer_content) 
            FILTER(WHERE rc.id_question IN ('2732164','2718008')), ' | ') AS reason_financ,
        ARRAY_JOIN(ARRAY_AGG(DISTINCT rc.answer_content) 
            FILTER(WHERE rc.id_question = '2718009'), ' | ') AS comment_csat
    FROM datalake_survicate.response_content rc
    LEFT JOIN datalake_survicate.survey_questions sq ON sq.id_question = rc.id_question
    LEFT JOIN datalake_survicate.survey_responses sr ON sr.id_response = rc.id_response
    WHERE sq.id_survey = '006af3a7ab9cdd3b' AND rc.ts_collected >= DATE('{load_start_date}')
    GROUP BY rc.id_response, rc.ts_collected, sr.response_url
),
base_final as (
SELECT
    nps.nome_campanha,
    nps.feedback_id,
    nps.posted_at,
    nps.offer_id,
    CASE 
        WHEN satisfaction_raw = 'Extremely happy' THEN 5
        WHEN satisfaction_raw = 'Happy' THEN 4
        WHEN satisfaction_raw = 'Neutral' THEN 3
        WHEN satisfaction_raw = 'Unsatisfied' THEN 2
        WHEN satisfaction_raw = 'Extremely unsatisfied' THEN 1
        ELSE NULL
    END AS rating,
    iv.internal_vendors_flag,
    CASE 
        WHEN fcf.legal_risk_analyst_email LIKE '%quintoandar.com.br' THEN 'quintoandar'
        WHEN fcf.legal_risk_analyst_email LIKE '%webhelpbr.com.br' THEN 'webhelp'
        ELSE 'quintoandar'
    END AS agent_company,
    fcf.legal_risk_analyst_email AS agent_email,
    n.id_user AS author_id,
    CASE WHEN n.id_user = dus.sk_seller THEN 'seller' ELSE 'buyer' END AS customer_type,
    a.seller_dilligence_status AS share_risco,
    a.has_used_fgts_in_payment,
    fcf.financing_bank,
    fran.franchise_name AS adjusted_franchise_name,
    CASE
        WHEN fran.franchise_name = 'QuintoAndar'
            AND fcf.payment_method IN ('FINANCED', 'FINANCED_USING_FGTS') 
            AND fcf.credit_model IN ('UNDEFINED', 'ATTA')    
        THEN TRUE
        ELSE FALSE
    END AS is_corban,
    nps.phone,
    nps.reason_financ,
    nps.comment_csat,
    CONCAT(nps.offer_id, CASE WHEN n.id_user = dus.sk_seller THEN '_seller' ELSE '_buyer' END) AS account_id,
    fcf.payment_method,
    fcf.city_group
FROM nps
LEFT JOIN tel_user n ON nps.phone = n.tel
LEFT JOIN post_specialist ps ON ps.sk_offer = nps.offer_id
LEFT JOIN fact_closing_flows fcf ON fcf.sk_offer = nps.offer_id
LEFT JOIN dw_sale.dim_sale_agreement a ON a.sk_offer = nps.offer_id
LEFT JOIN dim_user_sale dus ON dus.sk_offer = nps.offer_id
LEFT JOIN base_offers_internal_vendors iv ON iv.sk_offer = nps.offer_id
LEFT JOIN franchise_last_pre_analysis fran ON fran.sk_offer = nps.offer_id
QUALIFY ROW_NUMBER() OVER(PARTITION BY nps.offer_id, nps.phone ORDER BY nps.posted_at ASC) = 1)
SELECT 
  bf.nome_campanha as csat_campanha,
  bf.feedback_id,
  date_format(bf.posted_at, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  bf.author_id,
  bf.agent_email,
  bf.agent_company,
  bf.offer_id,
  bf.customer_type,
  bf.account_id,
  bf.payment_method,
  bf.internal_vendors_flag,
  case
      when bf.rating >= 4 then 'promoter'
      when bf.rating <= 2 then 'detractor'
      else 'passive'
    end as csat_score_category,
  bf.rating,
  CASE 
    WHEN NULLIF(bf.comment_csat, '') IS NULL 
        AND NULLIF(bf.reason_financ, '') IS NULL 
        THEN NULL
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_financ, '') IS NULL 
        AND bf.rating <= 2 
        THEN 'Motivo da minha insatisfação: ' || bf.comment_csat 
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_financ, '') IS NULL 
        AND bf.rating = 3 
        THEN 'Motivo da minha nota: ' || bf.comment_csat 
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_financ, '') IS NULL 
        AND bf.rating >= 4 
        THEN 'Motivo da minha satisfação: ' || bf.comment_csat 
    WHEN NULLIF(bf.comment_csat, '') IS NULL 
        AND NULLIF(bf.reason_financ, '') IS NOT NULL 
        AND bf.rating <= 2 
        THEN 'Justificativa: ' || bf.reason_financ
    WHEN NULLIF(bf.comment_csat, '') IS NULL 
        AND NULLIF(bf.reason_financ, '') IS NOT NULL 
        AND bf.rating = 3 
        THEN 'Justificativa: ' || bf.reason_financ  
    WHEN NULLIF(bf.comment_csat, '') IS NULL 
        AND NULLIF(bf.reason_financ, '') IS NOT NULL 
        AND bf.rating >= 4 
        THEN 'Justificativa: ' || bf.reason_financ 
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_financ, '') IS NOT NULL 
        AND bf.rating <= 2 
        THEN 'Motivo da minha insatisfação: ' || bf.comment_csat || ' Justificativa: ' || bf.reason_financ
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_financ, '') IS NOT NULL 
        AND bf.rating = 3 
        THEN 'Motivo da minha nota: ' || bf.comment_csat || ' Justificativa: ' || bf.reason_financ
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_financ, '') IS NOT NULL 
        AND bf.rating >= 4 
        THEN 'Motivo da minha satisfação: ' || bf.comment_csat || ' Justificativa: ' || bf.reason_financ
    ELSE NULL
  END AS text,
  bf.is_corban,
  bf.city_group,
  bf.adjusted_franchise_name,
  bf.share_risco,
  bf.has_used_fgts_in_payment,
  bf.financing_bank,
  year(bf.posted_at) AS year,
  month(bf.posted_at) AS month,
  day(bf.posted_at) AS day,
  NOW() AS ts_load
FROM 
    base_final AS bf 
WHERE 
    rating is not null
