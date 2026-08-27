/* CTE de dados de usuários (comprador e vendedor) */
WITH dim_user_sale AS (
  SELECT
    fo.sk_offer,
    fo.sk_house,
    fo.sk_buyer,
    REPLACE(du.telefone_principal, '+', '') AS phone_buyer,
    du.email AS email_buyer,
    du.nome AS name_buyer,
    fo.sk_owner AS sk_seller,
    REPLACE(sl.telefone_principal, '+', '') AS phone_seller,
    sl.email AS email_seller,
    sl.nome AS name_seller
  FROM dw_sale.fact_offers AS fo
  LEFT JOIN dw_public.dim_user AS du
    ON fo.sk_buyer = du.sk_user
  LEFT JOIN dw_public.dim_user AS sl
    ON fo.sk_owner = sl.sk_user
), base_offers_internal_vendors /* CTE com bandeira de vendedores internos */ AS (
  SELECT
    sk_offer,
    CASE
      WHEN payment_method IN ('FINANCED_USING_FGTS', 'FINANCED')
      AND credit_model IN ('UNDEFINED', 'ATTA')
      THEN TRUE
      WHEN payment_method IN ('FINANCED_USING_FGTS', 'FINANCED')
      AND credit_model = 'EXTERNAL'
      THEN FALSE
    END AS internal_vendors_flag
  FROM dw_sale.dim_offer
), offer /* CTE com dados principais da oferta */ AS (
  SELECT
    fo.sk_offer,
    CAST(dsa.ts_sale_agreement_signed AS DATE) AS ts_sale_agreement_signed,
    fo.sk_buyer,
    fo.sk_owner,
    sof.financing_bank,
    sof.payment_method,
    dsa.credit_model,
    dsa.closing_status,
    dsa.house_dilligence_status,
    dsa.seller_dilligence_status,
    dsa.report_dilligence_status,
    sof.bank_analysis_status,
    sof.payment_status,
    sof.credit_status,
    dsa.has_used_fgts_in_payment,
    dsa.has_seller_debt_payments,
    fo.last_price_offered_by_buyer AS sale_price,
    dsa.is_3p_supply,
    dsa.is_3p_demand,
    dsa.payment_model,
    sof.dt_house_registry_ended AS ts_house_registry_ended,
    dim.city_group,
    duser.email AS email_especialist,
    dsa.ccv_model,
    dsa.is_ccv_canceled
  FROM dw_sale.fact_offers AS fo
  JOIN dw_sale.dim_sale_agreement AS dsa
    ON fo.sk_offer = dsa.sk_offer
  LEFT JOIN dw_public.dim_region AS dim
    ON fo.sk_region = dim.sk_region
  LEFT JOIN dw_public.dim_user AS duser
    ON fo.sk_user_consultant = duser.id
  LEFT JOIN datalake_sale_offer_flows.sale_offer_flows AS sof
    ON fo.sk_offer = sof.id_offer
),
-- tickets CTE (one row per ticket after the window filter)
tickets AS (
  SELECT
    id_ticket,
    id_user,
    email,
    ts_ticket_ended,
    ts_sla_started,
    ts_closed,
    agent_company,
    offer_id,
    sk_last_analyst,
    channel
  FROM (
    SELECT
      em.id_ticket,
      em.id_user,
      an.email,
      ts_ticket_ended,
      ts_sla_started,
      ts_closed,
      CASE
        WHEN an.email LIKE '%webhelpbr.com.br'
        THEN 'webhelp'
        WHEN an.email LIKE '%quintoandar.com.br'
        THEN 'quintoandar'
        ELSE NULL
      END AS agent_company,
      tkt.sk_sale_offer AS offer_id,
      tkt.sk_last_analyst,
      tkt.channel,
      ROW_NUMBER() OVER (PARTITION BY em.id_user ORDER BY ts_sla_started DESC) AS _w
    FROM datalake_customer_support.email AS em
    LEFT JOIN dw_customer_support.fact_tickets AS tkt
      ON CAST(em.id_ticket AS BIGINT) = tkt.sk_ticket
    LEFT JOIN dw_customer_support.dim_ticket AS tkt2
      ON tkt2.sk_ticket = tkt.sk_ticket
    LEFT JOIN dw_customer_support.dim_department AS de
      ON de.sk_department = tkt.sk_main_department
    LEFT JOIN dw_customer_support.dim_analyst AS an
      ON tkt.sk_last_analyst = an.sk_analyst
    WHERE
      tkt.channel = 'email'
      AND tkt2.status IN ('closed', 'solved')
      AND de.department IN ('WH - Financiamento Interno [SALE] [POS] FRONT]', 'À Vista NM [SALE] [POS] [FRONT]', 'Atendimento Reativo [SALE] [POS] [FRONT]', 'Financiamento Externo [SALE] [POS] [FRONT]', 'Financiamento Interno [SALE] [POS] [FRONT]', 'Especialista N2 [SALE] [POS] [BACK]', 'CRI Financiamento Interno [SALE] [POS] [FRONT]', 'WH - À Vista [SALE] [POS] [FRONT]', 'WH - Financiamento Externo [SALE] [POS] [FRONT]', 'Closing Lab [RC]', 'Incubadora-Front [EoP] [Forsale]', 'WH - Híbridos [SALE] [POS] [FRONT]', 'WH - Consórcio [SALE][POS][FRONT]')
  ) AS _t
  WHERE
    _w = 1
), post_specialist /* CTE especialista do pós com ticket mais recente */ AS (
  SELECT DISTINCT
    sk_offer,
    id_user,
    email
  FROM offer
  LEFT JOIN tickets
    ON offer_id = sk_offer AND id_user = sk_buyer
), fact_closing_flows /* CTE com dados do fluxo de fechamento */ AS (
  SELECT
    fcf.sk_offer,
    dsa.payment_method,
    dsa.credit_model,
    sof.financing_bank,
    dr.city_group,
    fos.legal_risk_analyst_email
  FROM dw_sale.fact_closing_flows AS fcf
  LEFT JOIN dw_sale.dim_sale_agreement AS dsa
    ON fcf.sk_offer = dsa.sk_offer
  LEFT JOIN dw_sale.fact_offers AS fo
    ON fcf.sk_offer = fo.sk_offer
  LEFT JOIN dw_public.dim_region AS dr
    ON fo.sk_region = dr.sk_region
  LEFT JOIN datalake_sale_offer_flows.offer_specialists AS fos
    ON fos.id_offer = fcf.sk_offer
  LEFT JOIN datalake_sale_offer_flows.sale_offer_flows AS sof
    ON fcf.sk_offer = sof.id_offer
  WHERE
    dsa.payment_model = 'CCV_ASSISTANCE'
    AND dsa.is_ccv_canceled = FALSE
    AND dsa.ccv_model <> 'Not a 5A model'
), franchise_last_pre_analysis /* CTE com última análise da franquia */ AS (
  SELECT
    sk_offer,
    franchise_name
  FROM (
    SELECT
      sk_offer,
      franchise_name,
      ROW_NUMBER() OVER (PARTITION BY sk_offer ORDER BY ts_last_updated DESC) AS _w,
      ts_last_updated
    FROM dw_atta.fact_pre_analysis_proposal_flow AS fpp
    LEFT JOIN dw_atta.dim_franchise_atta AS dfr
      ON fpp.sk_franchise = dfr.sk_franchise
  ) AS _t
  WHERE
    _w = 1
), tel_user /* CTE com telefone vinculado a notificações */ AS (
  SELECT
    n.destination AS tel,
    n.id_user
  FROM datalake_jaiminho_clean.user_notifications AS n
  WHERE
    entity_name = 'postAcceptedDiligenceThermometerSurvey'
), nps /* CTE NPS com rating e motivos */ AS (
  SELECT
    'Diligência' AS nome_campanha,
    rc.id_response AS feedback_id,
    rc.ts_collected AS posted_at,
    PARSE_URL(sr.response_url, 'QUERY', 'offer') AS offer_id,
    PARSE_URL(sr.response_url, 'QUERY', 'tel') AS phone,
    MAX(CASE WHEN rc.id_question = '2718000' THEN rc.answer_content END) AS satisfaction_raw,
    ARRAY_JOIN(
      COLLECT_LIST(DISTINCT rc.answer_content) FILTER(WHERE
        rc.id_question IN ('2732165', '2718002')),
      ' | '
    ) AS reason_dd,
    ARRAY_JOIN(
      COLLECT_LIST(DISTINCT rc.answer_content) FILTER(WHERE
        rc.id_question = '2718003'),
      ' | '
    ) AS comment_csat
  FROM datalake_survicate.response_content AS rc
  LEFT JOIN datalake_survicate.survey_questions AS sq
    ON sq.id_question = rc.id_question
  LEFT JOIN datalake_survicate.survey_responses AS sr
    ON sr.id_response = rc.id_response
  WHERE
    sq.id_survey = '2087f705947a41b7'
  GROUP BY
    rc.id_response,
    rc.ts_collected,
    sr.response_url
), base_final AS (
  SELECT
    nome_campanha,
    feedback_id,
    posted_at,
    offer_id,
    rating,
    internal_vendors_flag,
    agent_company,
    agent_email,
    author_id,
    customer_type,
    share_risco,
    has_used_fgts_in_payment,
    financing_bank,
    adjusted_franchise_name,
    is_corban,
    phone,
    reason_dd,
    comment_csat,
    account_id,
    payment_method,
    city_group
  FROM (
    SELECT
      nps.nome_campanha,
      nps.feedback_id,
      nps.posted_at,
      nps.offer_id,
      CASE
        WHEN satisfaction_raw = 'Extremely happy'
        THEN 5
        WHEN satisfaction_raw = 'Happy'
        THEN 4
        WHEN satisfaction_raw = 'Neutral'
        THEN 3
        WHEN satisfaction_raw = 'Unsatisfied'
        THEN 2
        WHEN satisfaction_raw = 'Extremely unsatisfied'
        THEN 1
        ELSE NULL
      END AS rating,
      iv.internal_vendors_flag,
      CASE
        WHEN fcf.legal_risk_analyst_email LIKE '%quintoandar.com.br'
        THEN 'quintoandar'
        WHEN fcf.legal_risk_analyst_email LIKE '%webhelpbr.com.br'
        THEN 'webhelp'
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
      nps.reason_dd,
      nps.comment_csat,
      CONCAT(nps.offer_id, CASE WHEN n.id_user = dus.sk_seller THEN '_seller' ELSE '_buyer' END) AS account_id,
      fcf.payment_method,
      fcf.city_group,
      ROW_NUMBER() OVER (PARTITION BY nps.offer_id, nps.phone ORDER BY nps.posted_at ASC) AS _w
    FROM nps
    LEFT JOIN tel_user AS n
      ON nps.phone = n.tel
    LEFT JOIN post_specialist AS ps
      ON ps.sk_offer = nps.offer_id
    LEFT JOIN fact_closing_flows AS fcf
      ON fcf.sk_offer = nps.offer_id
    LEFT JOIN dw_sale.dim_sale_agreement AS a
      ON a.sk_offer = nps.offer_id
    LEFT JOIN dim_user_sale AS dus
      ON dus.sk_offer = nps.offer_id
    LEFT JOIN base_offers_internal_vendors AS iv
      ON iv.sk_offer = nps.offer_id
    LEFT JOIN franchise_last_pre_analysis AS fran
      ON fran.sk_offer = nps.offer_id
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  bf.nome_campanha AS csat_campanha,
  bf.feedback_id,
  DATE_FORMAT(bf.posted_at, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  bf.author_id,
  bf.agent_email,
  bf.agent_company,
  bf.offer_id,
  bf.customer_type,
  bf.account_id,
  bf.payment_method,
  bf.internal_vendors_flag,
  CASE
    WHEN bf.rating >= 4
    THEN 'promoter'
    WHEN bf.rating <= 2
    THEN 'detractor'
    ELSE 'passive'
  END AS csat_score_category,
  bf.rating,
  CASE
    WHEN NULLIF(bf.comment_csat, '') IS NULL AND NULLIF(bf.reason_dd, '') IS NULL
    THEN NULL
    WHEN NOT NULLIF(bf.comment_csat, '') IS NULL
    AND NULLIF(bf.reason_dd, '') IS NULL
    AND bf.rating <= 2
    THEN 'Motivo da minha insatisfação: ' || bf.comment_csat
    WHEN NOT NULLIF(bf.comment_csat, '') IS NULL
    AND NULLIF(bf.reason_dd, '') IS NULL
    AND bf.rating = 3
    THEN 'Motivo da minha nota: ' || bf.comment_csat
    WHEN NOT NULLIF(bf.comment_csat, '') IS NULL
    AND NULLIF(bf.reason_dd, '') IS NULL
    AND bf.rating >= 4
    THEN 'Motivo da minha satisfação: ' || bf.comment_csat
    WHEN NULLIF(bf.comment_csat, '') IS NULL
    AND NOT NULLIF(bf.reason_dd, '') IS NULL
    AND bf.rating <= 2
    THEN 'Justificativa: ' || bf.reason_dd
    WHEN NULLIF(bf.comment_csat, '') IS NULL
    AND NOT NULLIF(bf.reason_dd, '') IS NULL
    AND bf.rating = 3
    THEN 'Justificativa: ' || bf.reason_dd
    WHEN NULLIF(bf.comment_csat, '') IS NULL
    AND NOT NULLIF(bf.reason_dd, '') IS NULL
    AND bf.rating >= 4
    THEN 'Justificativa: ' || bf.reason_dd
    WHEN NOT NULLIF(bf.comment_csat, '') IS NULL
    AND NOT NULLIF(bf.reason_dd, '') IS NULL
    AND bf.rating <= 2
    THEN 'Motivo da minha insatisfação: ' || bf.comment_csat || ' Justificativa: ' || bf.reason_dd
    WHEN NOT NULLIF(bf.comment_csat, '') IS NULL
    AND NOT NULLIF(bf.reason_dd, '') IS NULL
    AND bf.rating = 3
    THEN 'Motivo da minha nota: ' || bf.comment_csat || ' Justificativa: ' || bf.reason_dd
    WHEN NOT NULLIF(bf.comment_csat, '') IS NULL
    AND NOT NULLIF(bf.reason_dd, '') IS NULL
    AND bf.rating >= 4
    THEN 'Motivo da minha satisfação: ' || bf.comment_csat || ' Justificativa: ' || bf.reason_dd
    ELSE NULL
  END AS text,
  bf.is_corban,
  bf.city_group,
  bf.adjusted_franchise_name,
  bf.share_risco,
  bf.has_used_fgts_in_payment,
  bf.financing_bank,
  YEAR(TO_DATE(bf.posted_at)) AS year,
  MONTH(TO_DATE(bf.posted_at)) AS month,
  DAY(TO_DATE(bf.posted_at)) AS day,
  NOW() AS ts_load
FROM base_final AS bf
WHERE
  NOT rating IS NULL AND bf.posted_at >= CAST('{load_start_date}' AS DATE)
