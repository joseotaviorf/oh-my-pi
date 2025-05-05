WITH dim_user_sale AS (
  SELECT 
    fo.sk_offer,
    fo.sk_house,
    fo.sk_buyer AS sk_buyer,
    du.email AS email_buyer,
    du.nome AS name_buyer,
    REPLACE(du.telefone_principal, '+', '') AS phone_buyer,
    fo.sk_owner AS sk_seller,
    sl.email AS email_seller,
    sl.nome AS name_seller,
    REPLACE(sl.telefone_principal, '+', '') AS phone_seller
  FROM dw_sale.fact_offers AS fo
  LEFT JOIN dw_public.dim_user du 
  ON fo.sk_buyer = du.sk_user
  LEFT JOIN dw_public.dim_user sl 
  ON fo.sk_owner = sl.sk_user
  ), base_offers_internal_vendors AS (
    SELECT 
      sk_offer,
      CASE
        WHEN payment_method IN ('FINANCED_USING_FGTS',
                                      'FINANCED')
          AND credit_model IN ('UNDEFINED',
                                        'ATTA') THEN TRUE
        WHEN payment_method IN ('FINANCED_USING_FGTS',
                                      'FINANCED')
          AND credit_model IN ('EXTERNAL') THEN FALSE
      END AS internal_vendors_flag
    FROM 
      dw_sale.dim_offer
   ), offer AS (
    SELECT 
      fo.sk_offer,
      date(dsa.ts_sale_agreement_signed) AS ts_sale_agreement_signed,
      fo.sk_buyer,
      fo.sk_owner,
      financing_bank,
      payment_method,
      dsa.CREDIT_MODEL,
      CLOSING_STATUS,
      HOUSE_DILLIGENCE_STATUS,
      SELLER_DILLIGENCE_STATUS,
      REPORT_DILLIGENCE_STATUS,
      BANK_ANALYSIS_STATUS,
      PAYMENT_STATUS,
      CREDIT_STATUS,
      dsa.HAS_USED_FGTS_IN_PAYMENT,
      HAS_SELLER_DEBT_PAYMENTS,
      fo.last_price_offered_by_buyer AS sale_price,
      dsa.IS_3P_SUPPLY,
      dsa.IS_3P_DEMAND,
      dsa.payment_model,
      ts_house_registry_ended,
      dim.city_group,
      duser.email AS email_especialist,
      dsa.ccv_model,
      dsa.is_ccv_canceled
    FROM 
      dw_sale.fact_offers AS fo
    JOIN dw_sale.dim_sale_agreement AS dsa 
      ON fo.sk_offer = dsa.sk_offer
    LEFT JOIN dw_public.dim_region AS dim 
      ON fo.sk_region=dim.sk_region
    LEFT JOIN dw_public.dim_user AS duser 
      ON fo.sk_user_consultant=duser.id
    ), tickets AS (
      SELECT DISTINCT
        em.id_ticket,
        em.id_user,
        an.email AS email,
        ts_ticket_ended,
        ts_sla_started,
        ts_closed,
        tkt.sk_sale_offer AS sk_offer,
        ROW_NUMBER() OVER (PARTITION BY em.id_user ORDER BY ts_sla_started DESC) AS order_ended_date,
        tkt.sk_last_analyst,
        tkt.channel
      FROM 
        datalake_customer_support.email em
      LEFT JOIN dw_customer_support.fact_tickets tkt 
        ON CAST(em.id_ticket AS BIGINT) = tkt.sk_ticket
      LEFT JOIN dw_customer_support.dim_ticket tkt2 
        ON tkt2.sk_ticket = tkt.sk_ticket
      LEFT JOIN dw_customer_support.dim_department de 
        ON de.sk_department = tkt.sk_main_department
      LEFT JOIN dw_customer_support.dim_analyst an 
        ON tkt.sk_last_analyst = an.sk_analyst
      WHERE 
        tkt.channel = 'email' 
        AND tkt2.status IN ('closed', 'solved')
        AND de.department IN (
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
  ), post_specialist AS (
    SELECT DISTINCT
      offer.sk_offer,
      id_user,
      email
    FROM 
      offer 
    LEFT JOIN tickets 
      ON offer.sk_offer = tickets.sk_offer 
      AND id_user = sk_buyer
    WHERE 
      order_ended_date = 1
  ), fact_closing_flows AS (
    SELECT 
      fcf.sk_offer,
      fcf.sk_house,
      financing_bank,
      dsa.payment_method,
      dsa.credit_model,
      dsa.business_unit,
      dsa.tags_from_salesflow,
      dsa.sale_price_agreed AS price_sale,
      dr.city_group,
      fos.legal_risk_analyst_email AS legal_risk_analyst_email,
      TO_DATE(CAST(NULLIF(fcf.sk_sale_agreement_created_date, -1) AS STRING), 'yyyymmdd') AS ts_sale_agreement_created_date,
      TO_DATE(CAST(NULLIF(fcf.sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') AS ts_sale_agreement_signed_date,
      TO_DATE(CAST(NULLIF(fcf.sk_legal_analysis_ended_date, -1) AS STRING), 'yyyymmdd') AS ts_legal_analysis_ended_date,
      TO_DATE(CAST(NULLIF(fcf.sk_onboarding_ended_date, -1) AS STRING), 'yyyymmdd') AS ts_onboarding_ended_date,
      TO_DATE(CAST(NULLIF(fcf.sk_house_registry_ended_date, -1) AS STRING), 'yyyymmdd') AS ts_house_registry_ended_date,
      TO_DATE(CAST(NULLIF(fcf.sk_financing_started_date, -1) AS STRING), 'yyyymmdd') AS ts_house_financing_started_date
    FROM 
      dw_sale.fact_closing_flows AS fcf
    LEFT JOIN dw_sale.dim_sale_agreement AS dsa 
    ON fcf.sk_offer = dsa.sk_offer
    LEFT JOIN dw_sale.fact_offers AS fo 
    ON fcf.sk_offer = fo.sk_offer
    LEFT JOIN dw_public.dim_region AS dr 
    ON fo.sk_region = dr.sk_region
    LEFT JOIN datalake_sale_offer_flows.offer_specialists AS fos 
    ON fos.id_offer = fcf.sk_offer
    WHERE 
    dsa.payment_model = 'CCV_ASSISTANCE'
    AND dsa.is_ccv_canceled = FALSE
    AND dsa.ccv_model != 'Not a 5A model' --AND  TO_DATE(CAST(NULLIF(fcf.sk_sale_agreement_signed_date,-1) AS varchar),'yyyymmdd') >= DATE_ADD('day',-180,NOW())
),
  franchise_last_pre_analysis AS (
    SELECT 
      sk_offer,
      franchise_name
    FROM 
      dw_atta.fact_pre_analysis_proposal_flow AS fpp
    LEFT JOIN
      dw_atta.dim_franchise_atta AS dfr 
      ON fpp.sk_franchise = dfr.sk_franchise
    QUALIFY
      row_number() over(PARTITION BY sk_offer ORDER BY ts_last_updated DESC) = 1
), tel_user AS (
  SELECT 
    n.destination AS tel,
    n.id_user
   FROM datalake_jaiminho_clean.user_notifications AS n
   WHERE entity_name IN ('postAcceptedDiligenceThermometerSurvey')
), base_final AS (
  SELECT DISTINCT 
    'Diligência' AS nome_campanha,
    rc.id_response AS feedback_id,
    date(rc.ts_collected) AS posted_at,
    get_json_object(sr.response_url, '$.offer') AS offer_id,
    CASE
      WHEN ARRAY_AGG(DISTINCT rc.answer_content) FILTER(
                                                                         WHERE rc.id_question = '2718000')[1] = 'Extremely happy' THEN 5
                       WHEN ARRAY_AGG(DISTINCT rc.answer_content) FILTER(
                                                                         WHERE rc.id_question = '2718000')[1] = 'Happy' THEN 4
                       WHEN ARRAY_AGG(DISTINCT rc.answer_content) FILTER(
                                                                         WHERE rc.id_question = '2718000')[1] = 'Neutral' THEN 3
                       WHEN ARRAY_AGG(DISTINCT rc.answer_content) FILTER(
                                                                         WHERE rc.id_question = '2718000')[1] = 'Unsatisfied' THEN 2
                       WHEN ARRAY_AGG(DISTINCT rc.answer_content) FILTER(
                                                                         WHERE rc.id_question = '2718000')[1] = 'Extremely unsatisfied' THEN 1
                       ELSE NULL
    END AS rating ,
    iv.internal_vendors_flag AS internal_vendors_flag ,
    CASE
      WHEN fcf.legal_risk_analyst_email LIKE '%quintoandar.com.br' THEN 'quintoandar'
      WHEN fcf.legal_risk_analyst_email LIKE '%webhelpbr.com.br' THEN 'webhelp'
      ELSE 'quintoandar'
    END AS agent_company ,
    fcf.legal_risk_analyst_email AS agent_email,
    n.id_user AS author_id,
    CASE
      WHEN n.id_user=dus.sk_seller THEN 'seller'
      WHEN n.id_user=dus.sk_buyer THEN 'buyer'
    END AS customer_type ,
    a.seller_dilligence_status AS share_risco ,
    a.HAS_USED_FGTS_IN_PAYMENT AS has_used_fgts_in_payment,
    fcf.financing_bank,
    fran.franchise_name AS adjusted_franchise_name,
    CASE
        WHEN fran.franchise_name = 'QuintoAndar'
        AND fcf.payment_method in ('FINANCED','FINANCED_USING_FGTS') 
        AND fcf.credit_model IN('UNDEFINED','ATTA')    
        THEN TRUE
        ELSE FALSE
    END AS is_corban,
    PARSE_URL(sr.response_url, 'QUERY', 'tel') AS phone ,
                   ARRAY_JOIN(ARRAY_AGG(DISTINCT rc.answer_content) FILTER(
                                                                           WHERE rc.id_question IN ('2732165', '2718002')), ' | ') AS reason_dd ,
                   ARRAY_JOIN(ARRAY_AGG(DISTINCT rc.answer_content) FILTER(
                                                                           WHERE rc.id_question = '2718003'), ' | ') AS comment_csat ,
    concat(PARSE_URL(sr.response_url,'QUERY', 'offer'), CASE
                                                                               WHEN n.id_user = dus.sk_seller THEN '_seller'
                                                                               ELSE '_buyer'
     END) AS account_id,
    fcf.payment_method,
    fcf.city_group,
    ROW_NUMBER() OVER(PARTITION BY PARSE_URL(sr.response_url,'QUERY', 'offer'), PARSE_URL(sr.response_url,'QUERY' ,'tel') ORDER BY rc.ts_collected ASC) AS answer_order
   FROM datalake_survicate.response_content AS rc
   LEFT JOIN datalake_survicate.survey_questions AS sq 
    ON sq.id_question = rc.id_question
   LEFT JOIN datalake_survicate.survey_responses AS sr 
    ON sr.id_response = rc.id_response
   LEFT JOIN datalake_customer_support.email AS e 
    ON get_json_object(e.custom_fields, '$["[RC] ID Offer do Imóvel"]') = PARSE_URL(sr.response_url, 'QUERY' , 'offer')
   LEFT JOIN post_specialist AS ps 
    ON ps.sk_offer = PARSE_URL(sr.response_url, 'QUERY', 'offer')
   LEFT JOIN fact_closing_flows AS fcf 
    ON fcf.sk_offer = PARSE_URL(sr.response_url,'QUERY', 'offer')
   LEFT JOIN dw_sale.dim_sale_agreement AS a 
    ON a.sk_offer = PARSE_URL(sr.response_url,'QUERY', 'offer')
   LEFT JOIN dim_user_sale AS dus 
    ON dus.sk_offer = PARSE_URL(sr.response_url,'QUERY', 'offer')
   LEFT JOIN base_offers_internal_vendors AS iv 
    ON iv.sk_offer = PARSE_URL(sr.response_url,'QUERY', 'offer')
   LEFT JOIN franchise_last_pre_analysis AS fran 
    ON fran.sk_offer = PARSE_URL(sr.response_url,'QUERY', 'offer')
   LEFT JOIN tel_user AS n 
    ON '+'||trim(PARSE_URL(sr.response_url,'QUERY', 'tel')) = n.tel
   WHERE (sq.id_survey = '2087f705947a41b7')
     AND sq.dt_load = DATE_ADD(DAY, -1, CURRENT_DATE)
     AND rc.ts_collected>= date('2024-11-20')
   GROUP BY rc.ts_collected,
            1,
            2,
            3,
            4,
            6,
            7,
            8,
            9,
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            19,
            20,
            21)
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
        AND NULLIF(bf.reason_dd, '') IS NULL 
        THEN NULL
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_dd, '') IS NULL 
        AND bf.rating <= 2 
        THEN 'Motivo da minha insatisfação: ' || bf.comment_csat 
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_dd, '') IS NULL 
        AND bf.rating = 3 
        THEN 'Motivo da minha nota: ' || bf.comment_csat 
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_dd, '') IS NULL 
        AND bf.rating >= 4 
        THEN 'Motivo da minha satisfação: ' || bf.comment_csat 
    WHEN NULLIF(bf.comment_csat, '') IS NULL 
        AND NULLIF(bf.reason_dd, '') IS NOT NULL 
        AND bf.rating <= 2 
        THEN 'Justificativa: ' || bf.reason_dd 
    WHEN NULLIF(bf.comment_csat, '') IS NULL 
        AND NULLIF(bf.reason_dd, '') IS NOT NULL 
        AND bf.rating = 3 
        THEN 'Justificativa: ' || bf.reason_dd  
    WHEN NULLIF(bf.comment_csat, '') IS NULL 
        AND NULLIF(bf.reason_dd, '') IS NOT NULL 
        AND bf.rating >= 4 
        THEN 'Justificativa: ' || bf.reason_dd 
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_dd, '') IS NOT NULL 
        AND bf.rating <= 2 
        THEN 'Motivo da minha insatisfação: ' || bf.comment_csat || ' Justificativa: ' || bf.reason_dd
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_dd, '') IS NOT NULL 
        AND bf.rating = 3 
        THEN 'Motivo da minha nota: ' || bf.comment_csat || ' Justificativa: ' || bf.reason_dd
    WHEN NULLIF(bf.comment_csat, '') IS NOT NULL 
        AND NULLIF(bf.reason_dd, '') IS NOT NULL 
        AND bf.rating >= 4 
        THEN 'Motivo da minha satisfação: ' || bf.comment_csat || ' Justificativa: ' || bf.reason_dd
    ELSE NULL
  END AS text,
  bf.is_corban,
  bf.city_group,
  bf.adjusted_franchise_name,
  bf.share_risco,
  bf.has_used_fgts_in_payment,
  bf.financing_bank
from 
  base_final as bf 
where answer_order=1
and date(bf.posted_at) >= DATE ('2025-04-07')