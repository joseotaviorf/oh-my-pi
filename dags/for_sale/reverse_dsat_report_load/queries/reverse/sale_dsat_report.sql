WITH
dim_financed_proposal AS (
  SELECT
      fpp.sk_offer,
      CASE
          WHEN dpa.partner_name LIKE 'Franquia%' THEN 'FRANCHISE'
          WHEN dpa.partner_name LIKE '%Hub%'
               OR dpa.partner_name LIKE 'Carteira%'
               OR dpa.partner_name LIKE '5A HUB%'
               OR dpa.partner_name LIKE '5a >>%'
               OR dpa.partner_name LIKE '5A >>%'
               OR dpa.partner_name IS NULL THEN 'INTERNAL'
          ELSE 'EXTERNAL'
      END AS partner_type,
      MAX (COALESCE (DATE(fpp.ts_credit_ended), DATE(fpp.ts_credit_ended))) AS last_credit_ended,
      MAX(DATE(fpp.ts_financing_ended)) AS last_financing_ended
  FROM
      dw_atta.fact_pre_analysis_proposal_flow fpp
  LEFT JOIN
      dw_atta.dim_partner_atta dpa
      ON fpp.sk_partner = dpa.sk_partner
  WHERE
  fpp.sk_offer != '-1'
  GROUP BY 1,2),

sqs_table_two AS (
  SELECT DISTINCT
    fo.sk_offer,
    ca.partner_type,
    CASE
        WHEN (fo.ts_offer_dismissed IS NOT NULL
              AND fo.ts_offer_rescued IS NULL) THEN TRUE
        ELSE FALSE
    END AS is_offer_canceled,
    CASE
        WHEN ca.last_credit_ended IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_credit_ended,
    CASE
        WHEN ca.last_financing_ended IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_financing_ended
  FROM
    dw_sale.fact_offers AS fo
  LEFT JOIN
    dim_financed_proposal ca
      ON ca.sk_offer = fo.sk_offer
  WHERE
  fo.ts_offer_submitted >= DATE('2023-03-01')),

dim_user_sale AS (
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
  FROM
    dw_sale.fact_offers AS fo
  LEFT JOIN
    dw_public.dim_user du
    ON fo.sk_buyer = du.sk_user
   LEFT JOIN
    dw_public.dim_user sl
    ON fo.sk_owner = sl.sk_user
),

base_offers_internal_vendors AS (
  SELECT
    sk_offer,
    is_offer_canceled,
    is_credit_ended,
    is_financing_ended,
    partner_type
  FROM
   sqs_table_two
  WHERE
    is_offer_canceled = FALSE
    AND is_credit_ended = TRUE
    AND partner_type IN ('FRANCHISE',
                        'EXTERNAL')
),

base_answers_term_cash_20_dias as (
        SELECT distinct
            sq.id_survey AS id,
            rc.id_response AS response_uuid,
            parse_url(sr.response_url, 'QUERY', 'offer') as id_offer,
            ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082434')[0] as pergunta_carinhas,
            CASE
              WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082434')[0] = 'Extremely happy' then 5
              WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082434')[0] = 'Happy' then 4
              WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082434')[0] = 'Neutral' then 3
              WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082434')[0] = 'Unsatisfied' then 2
              WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082434')[0] = 'Extremely unsatisfied' then 1
              ELSE NULL
            END AS csat_score,
            ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082435'),' | ') AS dd,
            ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082436'),' | ') AS reason_dd,
            ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082437'),' | ') as suporte_pv,
            ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082438'),' | ') as reason_suport_pv,
            ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2093552'),' | ') as cartorio_parceiro,
            ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2093554'),' | ') as reason_cartorio_parceiro,
            ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082439'),' | ') as comment_csat,
            rc.ts_collected AS ts_first_response,
             parse_url(sr.response_url, 'QUERY', 'tel') as user_phone,
            'Cash_20_days' as survey,
             null as internal_vendors_flag,
             parse_url(sr.response_url, 'QUERY', 'offer') AS offer_rn
        FROM
            datalake_survicate.response_content AS rc
          LEFT JOIN
            datalake_survicate.survey_questions AS sq
              ON sq.id_question = rc.id_question
          LEFT JOIN datalake_survicate.survey_responses AS sr
              ON sr.id_response = rc.id_response
        LEFT JOIN base_offers_internal_vendors iv on iv.sk_offer = parse_url(sr.response_url, 'QUERY', 'offer')
        WHERE (sq.id_survey = 'd720ca30e55c361e') AND sq.dt_load = date_add(current_date(),-1)
        GROUP BY 1, 2, 3, 13, 14, 15
),

base_answers_term_financed_30_dias AS (
  SELECT DISTINCT
    sq.id_survey AS id,
    rc.id_response AS response_uuid,
    parse_url(sr.response_url, 'QUERY', 'offer') AS id_offer,
    ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082411')[0] AS pergunta_carinhas,
    CASE
       WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082411')[0] = 'Extremely happy' THEN 5
       WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082411')[0] = 'Happy' THEN 4
       WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082411')[0] = 'Neutral' THEN 3
       WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082411')[0] = 'Unsatisfied' THEN 2
       WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082411')[0] = 'Extremely unsatisfied' THEN 1
       ELSE NULL
    END AS csat_score,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082412'), ' | ') AS dd,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082413'), ' | ') AS reason_dd,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082414'), ' | ') AS suporte_pv,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082415'), ' | ') AS reason_suport_pv,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082418'), ' | ') AS comment_csat,
    rc.ts_collected AS ts_first_response,
    parse_url(sr.response_url, 'QUERY', 'tel') AS user_phone,
    'Financed_30_days' AS survey,
    CASE
      WHEN iv.is_credit_ended = TRUE THEN '1'
      ELSE NULL
    END AS internal_vendors_flag,
    parse_url(sr.response_url, 'QUERY', 'offer') AS offer_rn
   FROM
    datalake_survicate.response_content AS rc
   LEFT JOIN
    datalake_survicate.survey_questions AS sq
    ON sq.id_question = rc.id_question
   LEFT JOIN
    datalake_survicate.survey_responses AS sr
    ON sr.id_response = rc.id_response
   LEFT JOIN
    base_offers_internal_vendors iv
    ON iv.sk_offer = parse_url(sr.response_url, 'QUERY', 'offer')
   WHERE (sq.id_survey = '40105d91b649c2ac')
     AND sq.dt_load = DATE_ADD(CURRENT_DATE(), -1)
   GROUP BY 1, 2, 3, 11, 12, 13, 14
   ),

  base_answers_term_financed_60_dias AS (
  SELECT DISTINCT
    sq.id_survey AS id,
    rc.id_response AS response_uuid,
    parse_url(sr.response_url, 'QUERY', 'offer') AS id_offer,
    ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082422')[0] AS pergunta_carinhas,
    CASE WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082422')[0] = 'Extremely happy' THEN 5
         WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082422')[0] = 'Happy' THEN 4
         WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082422')[0] = 'Neutral' THEN 3
         WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082422')[0] = 'Unsatisfied' THEN 2
         WHEN ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082422')[0] = 'Extremely unsatisfied' THEN 1
         ELSE NULL
    END AS csat_score,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082423'), ' | ') AS suporte,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082424'), ' | ') AS reason_suporte,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082425'), ' | ') AS financiamento_externo,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082426'), ' | ') AS reason_financiamento_externo,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082427'), ' | ') AS financiamento_5a,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082428'), ' | ') AS reason_financiamento_5a,
    ARRAY_JOIN(ARRAY_AGG(rc.answer_content) FILTER(WHERE rc.id_question = '2082429'), ' | ') AS comment_csat,
    rc.ts_collected AS ts_first_response,
    parse_url(sr.response_url, 'QUERY', 'tel') AS user_phone,
    'Financed_60_days' AS survey,
    CASE
      WHEN iv.is_credit_ended = TRUE AND is_financing_ended = TRUE THEN '1'
      ELSE NULL
    END AS internal_vendors_flag,
    parse_url(sr.response_url, 'QUERY', 'offer') AS offer_rn
   FROM
    datalake_survicate.response_content AS rc
   LEFT JOIN
    datalake_survicate.survey_questions AS sq
      ON sq.id_question = rc.id_question
   LEFT JOIN
    datalake_survicate.survey_responses AS sr
      ON sr.id_response = rc.id_response
   LEFT JOIN
    base_offers_internal_vendors iv
      ON iv.sk_offer = parse_url(sr.response_url, 'QUERY', 'offer')
   WHERE
    (sq.id_survey = 'f46fd0a280fb6299')
    AND sq.dt_load = DATE_ADD(CURRENT_DATE(),-1)
   GROUP BY 1, 2, 3, 13, 14, 15, 16
  )

SELECT
  DATE(ts_first_response) AS date_answer,
  survey,
  id_offer,
  user_phone,
  csat_score,
  dd AS answers_2_questions,
  reason_dd AS reaons_2_question,
  suporte_pv AS answers_3_questions,
  reason_suport_pv AS reaons_3_question,
  cartorio_parceiro AS answers_4_questions,
  reason_cartorio_parceiro AS reaons_4_question,
  comment_csat AS COMMENT,
  internal_vendors_flag,
  ts_sale_agreement_cancelled,
  CASE
      WHEN trim(user_phone)=dus.phone_seller THEN 'seller'
      WHEN trim(user_phone)=dus.phone_buyer THEN 'buyer'
  END AS customer,
  YEAR(DATE(ts_first_response)) AS year,
  MONTH(DATE(ts_first_response)) AS month,
  DAY(DATE(ts_first_response)) AS day
FROM
  base_answers_term_cash_20_dias AS b20
LEFT JOIN
  dw_sale.dim_sale_agreement a
    ON a.sk_offer = b20.id_offer
LEFT JOIN
  dim_user_sale AS dus
    ON dus.sk_offer = b20.id_offer
WHERE
  DATE(ts_first_response) >= DATE ('2023-08-28')
  AND csat_score > 0
  AND ts_sale_agreement_cancelled IS NULL
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY b20.offer_rn ORDER BY b20.ts_first_response DESC) = 1

UNION

SELECT
  DATE(ts_first_response) AS date_answer,
  survey,
  id_offer,
  user_phone,
  csat_score,
  dd AS answers_2_question,
  reason_dd AS reaons_2_question,
  suporte_pv AS answers_3_question,
  reason_suport_pv AS reaons_3_question,
  NULL AS answers_4_question,
  NULL AS reaons_4_question,
  comment_csat AS COMMENT,
  internal_vendors_flag,
  ts_sale_agreement_cancelled,
  CASE
      WHEN trim(user_phone)=dus.phone_seller THEN 'seller'
      WHEN trim(user_phone)=dus.phone_buyer THEN 'buyer'
  END AS customer,
  YEAR(DATE(ts_first_response)) AS year,
  MONTH(DATE(ts_first_response)) AS month,
  DAY(DATE(ts_first_response)) AS day
FROM
  base_answers_term_financed_30_dias AS b30
LEFT JOIN
  dw_sale.dim_sale_agreement a
  ON a.sk_offer = b30.id_offer
LEFT JOIN
  dim_user_sale AS dus
  ON dus.sk_offer = b30.id_offer
WHERE
  DATE(ts_first_response) >= DATE ('2023-08-28')
  AND csat_score > 0
  AND ts_sale_agreement_cancelled IS NULL
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY b30.offer_rn ORDER BY b30.ts_first_response DESC) = 1

UNION

SELECT
  DATE(ts_first_response) AS date_answer,
  survey,
  id_offer,
  user_phone,
  csat_score,
  suporte AS answers_2_question,
  reason_suporte AS reasons_2_question,
  financiamento_externo AS answers_3_question,
  reason_financiamento_externo reasons_3_question,
  financiamento_5a AS answers_4_question,
  reason_financiamento_5a AS reasons_4_question,
  comment_csat AS COMMENT,
  internal_vendors_flag,
  ts_sale_agreement_cancelled,
  CASE
      WHEN trim(user_phone)=dus.phone_seller THEN 'seller'
      WHEN trim(user_phone)=dus.phone_buyer THEN 'buyer'
  END AS customer,
  YEAR(DATE(ts_first_response)) AS year,
  MONTH(DATE(ts_first_response)) AS month,
  DAY(DATE(ts_first_response)) AS day
FROM
  base_answers_term_financed_60_dias AS b60
LEFT JOIN
  dw_sale.dim_sale_agreement a
  ON a.sk_offer = b60.id_offer
LEFT JOIN
  dim_user_sale AS dus
  ON dus.sk_offer = b60.id_offer
WHERE
  DATE(ts_first_response) >= DATE ('2023-08-28')
  AND csat_score > 0
  AND ts_sale_agreement_cancelled IS NULL
  AND year = {year}
  AND month = {month}
  AND day = {day}
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY b60.offer_rn ORDER BY b60.ts_first_response DESC) = 1
