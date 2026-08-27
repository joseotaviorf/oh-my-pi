WITH base_answers AS (
  SELECT DISTINCT
    rc.id_response,
    rc.ts_collected AS response_date,
    sr.response_url,
    PARSE_URL(sr.response_url, 'QUERY', 'agent') AS email_agent,
    PARSE_URL(sr.response_url, 'QUERY', 'dt_disparo') AS dt_disparo,
    CASE
      WHEN response_url LIKE '%t_id=%7B%7B%'
      THEN REGEXP_EXTRACT(response_url, 't_id=%7B%7B([0-9]+)%7D%7D')
      WHEN response_url LIKE '%t_id={{%'
      THEN REGEXP_EXTRACT(response_url, 't_id=([0-9]+)')
      ELSE PARSE_URL(sr.response_url, 'QUERY', 't_id')
    END AS ticket_id,
    ARRAY_DISTINCT(
      COLLECT_LIST(
        CASE
          WHEN rc.id_question = '2729626' AND NOT rc.answer_content IS NULL
          THEN rc.answer_content
        END
      )
    ) AS pergunta_carinhas,
    CASE
      WHEN ARRAY_DISTINCT(
        COLLECT_LIST(
          CASE
            WHEN rc.id_question = '2729626' AND NOT rc.answer_content IS NULL
            THEN rc.answer_content
          END
        )
      )[0] = 'Extremely happy'
      THEN 5
      WHEN ARRAY_DISTINCT(
        COLLECT_LIST(
          CASE
            WHEN rc.id_question = '2729626' AND NOT rc.answer_content IS NULL
            THEN rc.answer_content
          END
        )
      )[0] = 'Happy'
      THEN 4
      WHEN ARRAY_DISTINCT(
        COLLECT_LIST(
          CASE
            WHEN rc.id_question = '2729626' AND NOT rc.answer_content IS NULL
            THEN rc.answer_content
          END
        )
      )[0] = 'Neutral'
      THEN 3
      WHEN ARRAY_DISTINCT(
        COLLECT_LIST(
          CASE
            WHEN rc.id_question = '2729626' AND NOT rc.answer_content IS NULL
            THEN rc.answer_content
          END
        )
      )[0] = 'Unsatisfied'
      THEN 2
      WHEN ARRAY_DISTINCT(
        COLLECT_LIST(
          CASE
            WHEN rc.id_question = '2729626' AND NOT rc.answer_content IS NULL
            THEN rc.answer_content
          END
        )
      )[0] = 'Extremely unsatisfied'
      THEN 1
      ELSE NULL
    END AS csat_score,
    ARRAY_JOIN(
      ARRAY_DISTINCT(
        COLLECT_LIST(
          CASE
            WHEN rc.id_question = '2729629' AND NOT rc.answer_content IS NULL
            THEN rc.answer_content
          END
        )
      ),
      ' | '
    ) AS resolution,
    ARRAY_JOIN(
      ARRAY_DISTINCT(
        COLLECT_LIST(
          CASE
            WHEN rc.id_question = '2729630' AND NOT rc.answer_content IS NULL
            THEN rc.answer_content
          END
        )
      ),
      ' | '
    ) AS need_help,
    ARRAY_JOIN(
      ARRAY_DISTINCT(
        COLLECT_LIST(
          CASE
            WHEN rc.id_question = '2729628' AND NOT rc.answer_content IS NULL
            THEN rc.answer_content
          END
        )
      ),
      ' | '
    ) AS comment
  FROM datalake_survicate.response_content AS rc
  LEFT JOIN datalake_survicate.survey_responses AS sr
    ON sr.id_response = rc.id_response
  LEFT JOIN datalake_survicate.survey_questions AS sq
    ON sq.id_question = rc.id_question
  WHERE
    (
      sq.id_survey = '2f81495a1a142887'
    )
  GROUP BY
    1,
    2,
    3
), dados_tickets AS (
  SELECT DISTINCT
    em.id_ticket,
    em.id_user,
    an.email AS agent_email,
    CASE
      WHEN an.email LIKE '%webhelpbr.com.br'
      THEN 'webhelp'
      WHEN an.email LIKE '%quintoandar.com.br'
      THEN 'quintoandar'
      ELSE NULL
    END AS agent_company,
    em.department,
    CAST(em.ts_ticket_started AS DATE) AS date_started,
    tkt.sk_sale_offer AS offer_id,
    CASE
      WHEN dt.custom_fields_map['[RC] Qual tipo de cliente?'] = 'sl_rc_'
      THEN 'seller'
      WHEN dt.custom_fields_map['[RC] Qual tipo de cliente?'] = 'by_rc_'
      THEN 'buyer'
      ELSE NULL
    END AS tipo_cliente
  FROM datalake_customer_support.email AS em
  LEFT JOIN dw_customer_support.fact_tickets AS tkt
    ON CAST(em.id_ticket AS BIGINT) = tkt.sk_ticket
  LEFT JOIN dw_customer_support.dim_analyst AS an
    ON tkt.sk_first_analyst = an.sk_analyst
  LEFT JOIN dw_customer_support.dim_ticket AS dt
    ON CAST(em.id_ticket AS BIGINT) = dt.sk_ticket
  WHERE
    em.channel = 'whatsapp'
  GROUP BY
    1,
    2,
    3,
    5,
    6,
    7,
    8
), franchise_last_pre_analysis AS (
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
), dados_offers AS (
  SELECT DISTINCT
    sa.sk_offer,
    CAST(sa.ts_sale_agreement_signed AS DATE) AS ccv_signed_date,
    sa.is_ccv_canceled,
    sa.payment_model,
    sa.CREDIT_MODEL,
    CASE
      WHEN sa.payment_method IN ('CASH', 'CASH_USING_FGTS')
      THEN 'CASH'
      WHEN sa.payment_method IN ('FINANCED', 'FINANCED_USING_FGTS')
      THEN 'FINANCED'
      ELSE NULL
    END AS payment_method,
    CASE
      WHEN sa.payment_method IN ('FINANCED', 'FINANCED_USING_FGTS')
      AND sa.CREDIT_MODEL IN ('UNDEFINED', 'ATTA')
      THEN TRUE
      ELSE FALSE
    END AS credit_model_flag,
    dr.city_group,
    sof.financing_bank
  FROM dw_sale.dim_sale_agreement AS sa
  LEFT JOIN dw_sale.fact_offers AS fo
    ON sa.sk_offer = fo.sk_offer
  LEFT JOIN dw_public.dim_region AS dr
    ON fo.sk_region = dr.sk_region
  LEFT JOIN datalake_sale_offer_flows.sale_offer_flows AS sof
    ON fo.sk_offer = sof.id_offer
), main_table AS (
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
  FROM (
    SELECT
      'RC' AS csat_campanha,
      csat.id_response AS feedback_id,
      DATE_FORMAT(csat.response_date, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
      csat.ticket_id AS id_ticket,
      tkt.id_user AS author_id,
      tkt.agent_email,
      tkt.agent_company,
      tkt.offer_id,
      tkt.tipo_cliente AS customer_type,
      CONCAT(
        tkt.offer_id,
        CASE WHEN tkt.tipo_cliente = 'seller' THEN '_seller' ELSE '_buyer' END
      ) AS account_id,
      offer.payment_method,
      offer.credit_model_flag AS internal_vendors_flag,
      CASE
        WHEN csat.csat_score >= 4
        THEN 'promoter'
        WHEN csat_score <= 2
        THEN 'detractor'
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
        AND offer.payment_model IN ('FINANCED', 'FINANCED_USING_FGTS')
        AND offer.CREDIT_MODEL IN ('UNDEFINED', 'ATTA')
        THEN TRUE
        ELSE FALSE
      END AS is_corban,
      offer.city_group,
      fran.franchise_name AS adjusted_franchise_name,
      a.seller_dilligence_status AS share_risco,
      a.HAS_USED_FGTS_IN_PAYMENT AS has_used_fgts_in_payment,
      offer.financing_bank,
      CASE WHEN csat.resolution = 'Sim' THEN TRUE ELSE FALSE END AS resolution,
      dim.group_name AS department,
      YEAR(TO_DATE(csat.response_date)) AS year,
      MONTH(TO_DATE(csat.response_date)) AS month,
      DAY(TO_DATE(csat.response_date)) AS day,
      NOW() AS ts_load,
      ROW_NUMBER() OVER (PARTITION BY csat.ticket_id ORDER BY DATE_FORMAT(csat.response_date, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') ASC) AS _w
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
      CAST(csat.response_date AS DATE) >= CAST('{load_start_date}' AS DATE)
      AND NOT ticket_id IN ('82683066', '82497086', '82494776', '82248542', '81944018', '81943831', '81941902', '81876390', '81870665', '81869979', '81804253', '81628610', '75376578', '75966095', '76167278', '76590026', '79111487', '79147953', '79448132', '79479820', '79832975', '79876465', '80480862', '80539921', '80549040', '80549802', '80562966', '80563216', '80570523', '80571241', '80571390', '81886440')
  ) AS _t
  WHERE
    _w = 1
)
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
FROM main_table
WHERE
  NOT rating IS NULL