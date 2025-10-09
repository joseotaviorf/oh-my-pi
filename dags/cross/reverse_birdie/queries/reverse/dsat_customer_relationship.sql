WITH base_answers AS (
SELECT DISTINCT
  rc.id_response,
  rc.ts_collected AS response_date,
  sr.response_url,
  PARSE_URL(sr.response_url,'QUERY', 'agent') AS email_agent,
  PARSE_URL(sr.response_url,'QUERY', 'dt_disparo') AS dt_disparo,
  CASE
    WHEN response_url LIKE '%t_id=%7B%7B%' THEN
      regexp_extract(response_url, 't_id=%7B%7B([0-9]+)%7D%7D', 1)
    WHEN response_url LIKE '%t_id={{%' THEN
      regexp_extract(response_url, 't_id=([0-9]+)', 1)
    ELSE
      PARSE_URL(sr.response_url, 'QUERY', 't_id')
  END AS ticket_id,
  ARRAY_DISTINCT(ARRAY_AGG(CASE WHEN rc.id_question = '2729626' AND rc.answer_content IS NOT NULL THEN rc.answer_content END)) AS pergunta_carinhas,
  CASE WHEN ARRAY_DISTINCT(ARRAY_AGG(CASE WHEN rc.id_question = '2729626' AND rc.answer_content IS NOT NULL THEN rc.answer_content END))[0] = 'Extremely happy' THEN 5
    WHEN ARRAY_DISTINCT(ARRAY_AGG(CASE WHEN rc.id_question = '2729626' AND rc.answer_content IS NOT NULL THEN rc.answer_content END))[0] = 'Happy' THEN 4
    WHEN ARRAY_DISTINCT(ARRAY_AGG(CASE WHEN rc.id_question = '2729626' AND rc.answer_content IS NOT NULL THEN rc.answer_content END))[0] = 'Neutral' THEN 3
    WHEN ARRAY_DISTINCT(ARRAY_AGG(CASE WHEN rc.id_question = '2729626' AND rc.answer_content IS NOT NULL THEN rc.answer_content END))[0] = 'Unsatisfied' THEN 2
    WHEN ARRAY_DISTINCT(ARRAY_AGG(CASE WHEN rc.id_question = '2729626' AND rc.answer_content IS NOT NULL THEN rc.answer_content END))[0] = 'Extremely unsatisfied' THEN 1
    ELSE NULL
  END AS csat_score,
  ARRAY_JOIN(ARRAY_DISTINCT(ARRAY_AGG(CASE WHEN rc.id_question = '2729629' AND rc.answer_content IS NOT NULL THEN rc.answer_content END)), ' | ') AS resolution,
  ARRAY_JOIN(ARRAY_DISTINCT(ARRAY_AGG(CASE WHEN rc.id_question = '2729630' AND rc.answer_content IS NOT NULL THEN rc.answer_content END)), ' | ') AS need_help,
  ARRAY_JOIN(ARRAY_DISTINCT(ARRAY_AGG(CASE WHEN rc.id_question = '2729628' AND rc.answer_content IS NOT NULL THEN rc.answer_content END)),' | ') AS comment
  FROM
    datalake_survicate.response_content AS rc
  LEFT JOIN datalake_survicate.survey_responses AS sr
    ON sr.id_response = rc.id_response
  LEFT JOIN datalake_survicate.survey_questions AS sq
    ON sq.id_question = rc.id_question
  WHERE (sq.id_survey = '2f81495a1a142887') 
    GROUP BY 1,2,3
),
dados_tickets AS (
  SELECT distinct
    em.id_ticket,
    em.id_user,
    an.email AS agent_email,
    CASE 
      WHEN an.email LIKE '%webhelpbr.com.br' THEN 'webhelp'
      WHEN an.email LIKE '%quintoandar.com.br' THEN 'quintoandar'
      ELSE NULL
    END AS agent_company,
    em.department,
    date(em.ts_ticket_started) AS date_started,
    tkt.sk_sale_offer AS offer_id,
    CASE
      WHEN dt.custom_fields_map['[RC] Qual tipo de cliente?'] = "sl_rc_" then 'seller'
      WHEN dt.custom_fields_map['[RC] Qual tipo de cliente?'] = "by_rc_" THEN 'buyer'
      ELSE NULL
    END AS tipo_cliente
  FROM datalake_customer_support.email em
  LEFT JOIN dw_customer_support.fact_tickets tkt
    ON CAST(em.id_ticket AS BIGINT) = tkt.sk_ticket
  LEFT JOIN dw_customer_support.dim_analyst an
    ON tkt.sk_first_analyst= an.sk_analyst
  LEFT JOIN dw_customer_support.dim_ticket AS dt
    ON CAST(em.id_ticket AS BIGINT) = dt.sk_ticket
  WHERE 
    em.channel = 'whatsapp'
  GROUP BY 
    1,2,3,5,6,7,8
  ),
franchise_last_pre_analysis AS (
  SELECT 
    sk_offer,
    franchise_name
  FROM 
    dw_atta.fact_pre_analysis_proposal_flow AS fpp
  LEFT JOIN dw_atta.dim_franchise_atta AS dfr 
    ON fpp.sk_franchise = dfr.sk_franchise
  QUALIFY
    row_number() over(PARTITION BY sk_offer ORDER BY ts_last_updated DESC) = 1
),
dados_offers AS (
  SELECT DISTINCT
    sa.sk_offer,
    DATE(sa.ts_sale_agreement_signed) AS ccv_signed_date,
    sa.is_ccv_canceled,
    sa.payment_model,
    CREDIT_MODEL,
    CASE
      WHEN payment_method in ('CASH','CASH_USING_FGTS') 
      THEN 'CASH'
      WHEN payment_method in ('FINANCED','FINANCED_USING_FGTS') 
      THEN 'FINANCED'
      ELSE NULL
    END AS payment_method,
    CASE 
      WHEN payment_method in ('FINANCED','FINANCED_USING_FGTS') 
      AND CREDIT_MODEL IN ('UNDEFINED','ATTA') 
      THEN TRUE
      ELSE false
    END AS credit_model_flag,
    dr.city_group,
    sa.financing_bank
  FROM dw_sale.dim_sale_agreement sa
  LEFT JOIN dw_sale.fact_offers AS fo
    ON sa.sk_offer = fo.sk_offer
  LEFT JOIN dw_public.dim_region AS dr
    ON fo.sk_region = dr.sk_region
), main_table as (
SELECT
  'RC' AS csat_campanha,
  csat.id_response AS feedback_id,
  date_format(csat.response_date, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  csat.ticket_id AS id_ticket,
  tkt.id_user AS author_id,
  tkt.agent_email,
  tkt.agent_company,
  tkt.offer_id,
  tkt.tipo_cliente AS customer_type,
  concat(tkt.offer_id, CASE WHEN tkt.tipo_cliente ='seller' THEN '_seller' ELSE '_buyer' END) AS account_id,
  offer.payment_method,
  offer.credit_model_flag AS internal_vendors_flag,
  CASE WHEN csat.csat_score>= 4 THEN 'promoter'
    WHEN csat_score <=2 then 'detractor' 
    ELSE 'passive' 
  END AS csat_score_category,
  csat.csat_score AS rating,
  CASE 
    WHEN csat.comment IS NULL 
    THEN 'No Signal | Nenhum comentário deixado pelo usuário.'
    WHEN csat.csat_score IN (1, 2) 
    THEN 'Insatisfeito: ' || CAST(csat.csat_score AS STRING) || ' - ' || csat.comment 
    WHEN csat.csat_score IN (4, 5) 
    THEN 'Satisfeito: ' || CAST(csat.csat_score AS STRING) || ' - ' || csat.comment
    ELSE 'Neutro: ' || CAST(csat.csat_score AS STRING) || ' - ' || csat.comment
  END AS text,
  CASE 
    WHEN fran.franchise_name = 'QuintoAndar' 
    AND offer.payment_model in ('FINANCED', 'FINANCED_USING_FGTS') 
    AND offer.CREDIT_MODEL in ('UNDEFINED', 'ATTA')
    THEN TRUE 
    ELSE FALSE 
  END AS is_corban,
  offer.city_group,
  fran.franchise_name AS adjusted_franchise_name,
  a.seller_dilligence_status AS share_risco,
  a.HAS_USED_FGTS_IN_PAYMENT AS has_used_fgts_in_payment,
  offer.financing_bank,
  CASE 
    WHEN csat.resolution='Sim' 
    THEN TRUE 
    ELSE FALSE 
  END AS resolution,
  dim.group_name AS department,
  year(csat.response_date) AS year,
  month(csat.response_date) AS month,
  day(csat.response_date) AS day,
  NOW() AS ts_load
FROM base_answers AS csat
LEFT JOIN dados_tickets AS tkt
  ON csat.ticket_id = tkt.id_ticket
LEFT JOIN dados_offers AS offer
  ON offer.sk_offer = tkt.offer_id
LEFT JOIN dw_customer_support.dim_ticket AS dim
  ON tkt.id_ticket = CAST(dim.sk_ticket AS STRING)
LEFT JOIN franchise_last_pre_analysis AS fran
  ON fran.sk_offer = offer.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement AS a 
  ON a.sk_offer = offer.sk_offer
WHERE 
  DATE(csat.response_date) >= DATE('{load_start_date}')
  AND ticket_id not in ('82683066',
  '82497086',
  '82494776',
  '82248542',
  '81944018',
  '81943831',
  '81941902',
  '81876390',
  '81870665',
  '81869979',
  '81804253',
  '81628610',
  '75376578',
  '75966095',
  '76167278',
  '76590026',
  '79111487',
  '79147953',
  '79448132',
  '79479820',
  '79832975',
  '79876465',
  '80480862',
  '80539921',
  '80549040',
  '80549802',
  '80562966',
  '80563216',
  '80570523',
  '80571241',
  '80571390',
  '81886440')
QUALIFY 
  ROW_NUMBER() over(PARTITION BY id_ticket ORDER BY posted_at ASC) = 1)
SELECT
  csat_campanha,
  feedback_id,
  posted_at,
  id_ticket,
  author_id,
  agent_email,
  agent_company,
  offer_id,
  customer_type,
  account_id,
  payment_method,
  internal_vendors_flag,
  csat_score_category,
  rating,
  text,
  is_corban,
  city_group,
  adjusted_franchise_name,
  share_risco,
  has_used_fgts_in_payment,
  financing_bank,
  resolution,
  department,
  year,
  month,
  day,
  ts_load
FROM 
  main_table
WHERE
  rating IS NOT NULL