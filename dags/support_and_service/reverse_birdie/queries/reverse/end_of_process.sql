with nps AS (
    SELECT
       DISTINCT ans.sk_nps_answer,
       sk_contract, 
       disp.sk_user,
       sk_house_listing,
       disp.sk_offer,
       metric_group,
       score,
       score_category,
       comment,
       ts_answered,
       date AS sent_date,
       camp.main_channel
    FROM 
        dw_customer_satisfaction.dim_nps_answer AS ans
    LEFT JOIN dw_customer_satisfaction.fact_nps_dispatches AS disp 
        ON disp.sk_nps_answer=ans.sk_nps_answer
    LEFT JOIN dw_customer_satisfaction.dim_nps_campaign AS camp 
        ON camp.sk_nps_campaign=disp.sk_nps_campaign
    LEFT JOIN dw_public.dim_date AS dd 
        ON dd.sk_date = disp.sk_sent_date
    WHERE 
        is_answered = true 
        AND metric_group like '%endofprocess%' 
    ORDER BY
        sk_nps_answer
),
justification AS (
    SELECT 
        sk_nps_answer,
        ARRAY_JOIN(ARRAY_AGG(justification), ', ') AS justifications 
    FROM 
        dw_customer_satisfaction.fact_nps_answer_justifications
    GROUP BY 
        1
),
offer AS (
    SELECT 
        fo.sk_offer,
        dsa.ts_sale_agreement_signed AS ts_sale_agreement_signed,
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
        fo.last_price_offered_by_buyer as sale_price,
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
),
aux_franchise AS (
    SELECT 
        sk_offer,
        franchise_name,
        row_number() over(PARTITION BY sk_offer ORDER BY ts_last_updated DESC) AS update_order
    FROM 
        dw_atta.fact_pre_analysis_proposal_flow AS fpp
    LEFT JOIN
      dw_atta.dim_franchise_atta AS dfr ON fpp.sk_franchise = dfr.sk_franchise
),
franchise_last_pre_analysis AS (
    SELECT 
        sk_offer,
        franchise_name
    FROM 
        aux_franchise
    WHERE 
        update_order = 1
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
),
webhelp as(
    SELECT 
        DISTINCT fcf.sk_offer,
        t.email AS post_specialist_email
    FROM
        offer fcf
    LEFT JOIN 
        post_specialist t ON fcf.sk_offer = t.sk_offer
    WHERE 
        payment_model = 'CCV_ASSISTANCE' 
        AND is_ccv_canceled = false
        AND ccv_model != 'Not a 5A model'
)

SELECT DISTINCT
    'eop' as nome_campanha,
    date_format(nps.ts_answered, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
    date(ts_sale_agreement_signed) as ts_sale_agreement_signed,
    nps.sk_nps_answer as feedback_id,
    nps.sk_user as author_id,
    nps.sk_offer as offer_id,
    concat( nps.sk_offer,case when nps.metric_group ='sellerendofprocess' then '_seller' else '_buyer' end )as account_id,
    case when nps.metric_group ='sellerendofprocess' then 'seller' else 'buyer' end as customer_type,
    nps.score as rating,
    nps.score_category AS csat_score_category,
    CASE 
        WHEN 
            offer.financing_bank is NULL 
            OR offer.financing_bank = 'Outro' 
            OR offer.financing_bank = 'NA' 
        THEN 'Banco Indefinido' 
        ELSE offer.financing_bank 
    END AS financing_bank,
    CASE 
        WHEN 
            do.payment_method in ('CASH','CASH_USING_FGTS') 
        THEN 'CASH'
        WHEN 
            do.payment_method in ('FINANCED','FINANCED_USING_FGTS') 
        THEN 'FINANCED'
        ELSE NULL
    END AS payment_method,
    CASE 
        WHEN 
            offer.payment_method in ('FINANCED','FINANCED_USING_FGTS') AND offer.CREDIT_MODEL IN('UNDEFINED','ATTA')
        THEN 'TRUE'
        ELSE 'FALSE' 
    END AS internal_vendors_flag,
    CASE 
        WHEN
            do.payment_method in ('FINANCED','FINANCED_USING_FGTS') 
        THEN iv.franchise_name
       ELSE NULL 
    END AS adjusted_franchise_name,
    offer.SELLER_DILLIGENCE_STATUS as share_risco,
    --date_diff('day', ts_sale_agreement_signed, ts_house_registry_ended) AS LTCCV2CRI,
    Case when date_diff(DAY, ts_sale_agreement_signed, ts_house_registry_ended) >141 then '141d+' 
    when date_diff(DAY, ts_sale_agreement_signed, ts_house_registry_ended) >100 then '101d - 140d' 
    when date_diff(DAY, ts_sale_agreement_signed, ts_house_registry_ended) >60 then '61d - 100d' 
    when date_diff(DAY, ts_sale_agreement_signed, ts_house_registry_ended) >0 then '0d - 60d'
    else null end as range_lt_ccv2cri,
    offer.HAS_USED_FGTS_IN_PAYMENT as has_used_fgts_in_payment,
    --nps.comment,
    --j.justifications,
     CASE 
  WHEN NULLIF(nps.comment, '') IS NULL 
       AND NULLIF(j.justifications, '') IS NULL 
       THEN NULL
  WHEN NULLIF(nps.comment, '') IS NOT NULL 
       AND NULLIF(j.justifications, '') IS NULL 
       AND nps.score <= 6 
       THEN 'Motivo da minha insatisfação: ' || nps.comment 
  WHEN NULLIF(nps.comment, '') IS NOT NULL 
       AND NULLIF(j.justifications, '') IS NULL 
       AND nps.score IN (7,8) 
       THEN 'Motivo da minha nota: ' || nps.comment 
  WHEN NULLIF(nps.comment, '') IS NOT NULL 
       AND NULLIF(j.justifications, '') IS NULL 
       AND nps.score >= 9 
       THEN 'Motivo da minha satisfação: ' || nps.comment 
  WHEN NULLIF(nps.comment, '') IS NULL 
       AND NULLIF(j.justifications, '') IS NOT NULL 
       AND nps.score <= 6 
       THEN 'Justificativa: ' || j.justifications 
  WHEN NULLIF(nps.comment, '') IS NULL 
       AND NULLIF(j.justifications, '') IS NOT NULL 
       AND nps.score IN (7,8) 
       THEN 'Justificativa: ' || j.justifications  
  WHEN NULLIF(nps.comment, '') IS NULL 
       AND NULLIF(j.justifications, '') IS NOT NULL 
       AND nps.score >= 9 
       THEN 'Justificativa: ' || j.justifications 
  WHEN NULLIF(nps.comment, '') IS NOT NULL 
       AND NULLIF(j.justifications, '') IS NOT NULL 
       AND nps.score <= 6 
       THEN 'Motivo da minha insatisfação: ' || nps.comment || ' Justificativa: ' || j.justifications
  WHEN NULLIF(nps.comment, '') IS NOT NULL 
       AND NULLIF(j.justifications, '') IS NOT NULL 
       AND nps.score IN (7,8) 
       THEN 'Motivo da minha nota: ' || nps.comment || ' Justificativa: ' || j.justifications
  WHEN NULLIF(nps.comment, '') IS NOT NULL 
       AND NULLIF(j.justifications, '') IS NOT NULL 
       AND nps.score >= 9 
       THEN 'Motivo da minha satisfação: ' || nps.comment || ' Justificativa: ' || j.justifications
  ELSE NULL
END AS text,
    CASE
        WHEN iv.franchise_name = 'QuintoAndar'
        AND offer.payment_method in ('FINANCED','FINANCED_USING_FGTS') 
        AND offer.CREDIT_MODEL IN('UNDEFINED','ATTA')    
        THEN TRUE
        ELSE FALSE
    END AS is_corban,
    offer.city_group,
    CASE
            WHEN 
                ts_sale_agreement_signed < DATE '2024-04-05' 
            THEN 'quintoandar'
            WHEN 
                ts_sale_agreement_signed >= DATE '2024-04-05' AND wh.post_specialist_email LIKE '%quintoandar.com.br' 
            THEN 'quintoandar'
            WHEN 
                ts_sale_agreement_signed >= DATE '2024-04-05' AND wh.post_specialist_email LIKE '%webhelpbr.com.br' 
            THEN 'webhelp'
            WHEN 
                ts_sale_agreement_signed >= DATE '2024-04-05' AND wh.post_specialist_email IS NULL
            THEN 'quintoandar'
            ELSE 'quintoandar'
        END AS agent_company,
    wh.post_specialist_email as agent_email,
    year(nps.ts_answered) AS year,
    month(nps.ts_answered) AS month,
    day(nps.ts_answered) AS day,
    NOW() AS ts_load
FROM 
    nps 
LEFT JOIN offer 
    ON nps.sk_offer = offer.sk_offer
LEFT JOIN dw_sale.dim_offer do 
    ON do.sk_offer = nps.sk_offer 
LEFT JOIN franchise_last_pre_analysis AS iv 
    ON iv.sk_offer=nps.sk_offer
LEFT JOIN webhelp AS wh
    ON wh.sk_offer=nps.sk_offer
LEFT JOIN justification AS j 
    ON nps.sk_nps_answer=j.sk_nps_answer
WHERE
    DATE(nps.ts_answered) >= DATE('{load_start_date}')