WITH dados_offers as (
  SELECT distinct
    sa.sk_offer,
    date_format(sa.ts_sale_agreement_signed, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS ccv_signed_date,
    CASE
      WHEN payment_method in ('CASH','CASH_USING_FGTS') THEN 'CASH'
      WHEN payment_method in ('FINANCED','FINANCED_USING_FGTS') THEN 'FINANCED'
      ELSE NULL
    END AS payment_method,
    CASE 
      WHEN payment_method in ('FINANCED','FINANCED_USING_FGTS') AND CREDIT_MODEL IN ('UNDEFINED','ATTA') THEN 1
      ELSE NULL
    END AS credit_model_flag,
      dr.city_group,
      CREDIT_MODEL,
      sa.financing_bank,
      sa.seller_dilligence_status as share_risco,
      sa.HAS_USED_FGTS_IN_PAYMENT as has_used_fgts_in_payment
  FROM dw_sale.dim_sale_agreement sa
  LEFT JOIN dw_sale.fact_offers AS fo
    ON sa.sk_offer = fo.sk_offer
  LEFT JOIN dw_public.dim_region AS dr
    ON fo.sk_region = dr.sk_region
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
      row_number() over (PARTITION BY sk_offer ORDER BY ts_last_updated DESC) = 1
) SELECT 
  'RC' as csat_campanha,
  zes.response_uuid AS feedback_id,
  date_format(ftc.ts_last_response, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  ft.sk_ticket AS ticket_id,
  ft.sk_user as author_id,
  da.email AS agent_email,
  da.agent_organization AS agent_company,
  ft.sk_sale_offer AS offer_id,
  dt.customer_type,
  concat(ft.sk_sale_offer, '_', dt.customer_type_tag) as account_id,
  offer.payment_method,
  offer.credit_model_flag as internal_vendors_flag,
  CASE
    WHEN zes.csat_score >= 4 THEN 'promoter'
    WHEN zes.csat_score <=2 THEN 'detractor'
    ELSE 'passive'
  END AS csat_score_category,
  zes.csat_score AS rating,
  zes.user_comment AS comment,
  CASE 
    WHEN zes.user_comment IS NULL THEN 'No Signal | Nenhum comentário deixado pelo usuário.'
    WHEN zes.csat_score IN (1, 2) THEN 'Insatisfeito: ' || CAST(zes.csat_score AS STRING) || ' - ' || zes.user_comment 
    WHEN zes.csat_score IN (4, 5) THEN 'Satisfeito: ' || CAST(zes.csat_score AS STRING) || ' - ' || zes.user_comment
    ELSE 'Neutro: ' || CAST(zes.csat_score AS STRING) || ' - ' || zes.csat_score
  END AS text,
  CASE
    WHEN fran.franchise_name = 'QuintoAndar'
    AND offer.payment_method in ('FINANCED','FINANCED_USING_FGTS') 
    AND offer.CREDIT_MODEL IN('UNDEFINED','ATTA')    
    THEN TRUE
    ELSE FALSE
  END AS is_corban,
  offer.city_group,
  fran.franchise_name as adjusted_franchise_name,
  offer.share_risco,
  offer.has_used_fgts_in_payment,
  offer.financing_bank,
  COALESCE (ftc.is_solved, false) AS resolution,
  dtk.group_name as department,
  year(ftc.ts_last_response) AS year,
  month(ftc.ts_last_response) AS month,
  day(ftc.ts_last_response) AS day,
  NOW() AS ts_load
FROM dw_customer_support.fact_tickets AS ft 
LEFT JOIN dw_customer_support.dim_analyst AS da
  ON da.sk_analyst = ft.sk_last_analyst
LEFT JOIN dw_customer_support.dim_taxonomy AS dt 
  ON dt.sk_taxonomy = ft.sk_taxonomy 
LEFT JOIN dw_satisfaction_rating.fact_ticket_csat AS ftc
  ON ftc.sk_ticket = ft.sk_ticket
LEFT JOIN dw_customer_support.dim_ticket AS dtk
  ON dtk.sk_ticket = ft.sk_ticket
LEFT JOIN dados_offers AS offer
  ON offer.sk_offer = ft.sk_sale_offer
LEFT JOIN franchise_last_pre_analysis as fran
  ON fran.sk_offer = offer.sk_offer
LEFT JOIN datalake_survicate.zendesk_email_surveys AS zes
  ON CAST(zes.id_ticket AS BIGINT) = ft.sk_ticket
WHERE 
dtk.channel = 'whatsapp'
AND DATE(ftc.ts_last_response) >= DATE('{load_start_date}')
AND ft.sk_ticket NOT IN ('82683066',
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