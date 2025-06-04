WITH offer AS (
  SELECT
      fo.sk_offer,
      financing_bank,
      payment_method,
      dsa.ts_sale_agreement_signed AS ts_sale_agreement_signed,
      dsa.CREDIT_MODEL,
      SELLER_DILLIGENCE_STATUS,
      COALESCE(dim.city_group, dim2.city_group) AS city_group
  FROM dw_sale.fact_offers AS fo
  JOIN dw_sale.dim_sale_agreement AS dsa 
    ON fo.sk_offer = dsa.sk_offer
  LEFT JOIN dw_sale.dim_listing AS dl
    ON fo.sk_house = dl.sk_house
  LEFT JOIN dw_sale.fact_listings AS fl 
    ON dl.sk_sale_listing = fl.sk_sale_listing
  LEFT JOIN dw_public.dim_region AS dim 
    ON fo.sk_region = dim.sk_region
  LEFT JOIN dw_public.dim_region AS dim2 
    ON fl.sk_region = dim2.sk_region
),
justification AS (
  SELECT
      sk_nps_answer,
      ARRAY_JOIN(ARRAY_AGG(justification), ', ') AS justifications
  FROM
      dw_customer_satisfaction.fact_nps_answer_justifications
  WHERE justification not like '%?'
  GROUP BY
      1
),
visits AS (
  SELECT
  sk_buyer,
  city_group,
  ROW_NUMBER() OVER (PARTITION BY sk_buyer ORDER BY ts_booking_created DESC) AS rank_visit
  FROM dw_sale.fact_visits AS visits
  LEFT JOIN dw_public.dim_region AS dim ON visits.sk_region = dim.sk_region
  ),
listings as (
  select
  sk_owner,
  city_group,
  ROW_NUMBER() OVER (PARTITION BY sk_owner ORDER BY sk_last_depublication_date DESC) AS rank_depublication
  from dw_sale.fact_listings AS listings
  LEFT JOIN dw_public.dim_region AS dim 
  ON listings.sk_region = dim.sk_region
)
,dim_agent_region_max AS (
  SELECT
    sk_agent,
    sk_regions_date,
    SUBSTR(area, 1, 3) area,
    RANK () OVER (PARTITION BY sk_agent ORDER BY sk_regions_date DESC) rank_
  FROM dw_public.dim_agent_region
  WHERE area IS NOT NULL
)
,dim_region AS (
  SELECT distinct
    SUBSTR(region_code, 1, 3) AS region_code,
    city_group,
    city_name
  FROM dw_public.dim_region
)
,final AS (
  SELECT distinct
    date(ans.ts_answered) as posted_at,
    date(offer.ts_sale_agreement_signed) as ts_sale_agreement_signed,
    ans.sk_nps_answer as feedback_id,
    CASE WHEN f.id_broker IS NOT NULL THEN f.id_broker ELSE disp.sk_user END as author_id,
    CASE WHEN disp.sk_offer = '-1' THEN NULL ELSE disp.sk_offer END AS sk_offer,
    disp.sk_offer as account_id,
    CASE WHEN metric_group ='sellerendofprocess' 
      and camp.sk_nps_campaign in ('quintoandar249','quintoandar250','quintoandar297','quintoandar330','quintoandar479','quintoandar480')
      THEN 'seller'
      WHEN camp.sk_nps_campaign in ('quintoandar249','quintoandar250','quintoandar297','quintoandar330','quintoandar479','quintoandar480') THEN 'seller'
      WHEN camp.sk_nps_campaign in ('quintoandar251','quintoandar252','quintoandar253','quintoandar254','quintoandar298','quintoandar331','quintoandar454','quintoandar455')
      THEN 'buyer' ELSE NULL 
    END AS metric_group,
    disp.score,
    score_category,
    comment,
    CASE
        WHEN
              (offer.financing_bank is NULL
              OR offer.financing_bank = 'Outro'
              OR offer.financing_bank = 'NA')
              AND camp.sk_nps_campaign in ('quintoandar249','quintoandar250','quintoandar251','quintoandar252','quintoandar253','quintoandar254','quintoandar297','quintoandar298','quintoandar330','quintoandar331','quintoandar454','quintoandar455','quintoandar479','quintoandar480')
          THEN 'Banco Indefinido'
          WHEN camp.sk_nps_campaign in ('quintoandar249','quintoandar250','quintoandar251','quintoandar252','quintoandar253','quintoandar254','quintoandar297','quintoandar298','quintoandar330','quintoandar331','quintoandar454','quintoandar455','quintoandar479','quintoandar480')
          THEN offer.financing_bank
          ELSE NULL
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
            AND camp.sk_nps_campaign in ('quintoandar249','quintoandar250','quintoandar251','quintoandar252','quintoandar253','quintoandar254','quintoandar297','quintoandar298','quintoandar330','quintoandar331','quintoandar454','quintoandar455','quintoandar479','quintoandar480')
        THEN 'TRUE'
        WHEN camp.sk_nps_campaign in ('quintoandar249','quintoandar250','quintoandar251','quintoandar252','quintoandar253','quintoandar254','quintoandar297','quintoandar298','quintoandar330','quintoandar331','quintoandar454','quintoandar455','quintoandar479','quintoandar480')
        THEN 'FALSE' ELSE NULL
    END AS internal_vendors_flag,
    offer.SELLER_DILLIGENCE_STATUS,
    justifications,
    camp.name AS campaing,
    COALESCE(
    NULLIF(offer.city_group, 'NÃO INFORMADO'),
    NULLIF(visits.city_group, 'NÃO INFORMADO'),
    NULLIF(listings.city_group, 'NÃO INFORMADO'),
    NULLIF(region_.city_group, 'NÃO INFORMADO'),
    NULLIF(region_2.city_group, 'NÃO INFORMADO'),
    NULLIF(region_3.city_group, 'NÃO INFORMADO'),
    NULLIF(user_velo.city, 'NÃO INFORMADO'),
    NULLIF(region_4.city_group, 'NÃO INFORMADO'),
    NULLIF(disp.city, 'NÃO INFORMADO'),
    NULLIF(dim_user_last.cidade, 'NÃO INFORMADO'),
    NULLIF(dim_region_5.city_name, 'NÃO INFORMADO')
    ) AS city_name,
    CASE
        WHEN (camp.metric_group = 'adondevivir')
            OR (camp.metric_group = 'urbania') THEN 'Peru'
        WHEN camp.metric_group = 'inmuebles' THEN 'Mexico'
        WHEN camp.metric_group = 'zonaprop' THEN 'Argentina'
        WHEN (camp.metric_group = 'imovelweb')
            OR (camp.metric_group = 'casamineira') THEN 'Brasil'
        WHEN camp.metric_group = 'plusvalia' THEN 'Ecuador'
        WHEN camp.metric_group = 'compreoaquille' THEN 'Panama'
        ELSE NULL
    END AS country,
    camp.sk_nps_campaign
  FROM dw_customer_satisfaction.dim_nps_answer AS ans
  LEFT JOIN dw_customer_satisfaction.fact_nps_dispatches AS disp 
    ON ans.sk_nps_answer=disp.sk_nps_answer
  INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS camp 
    ON disp.sk_nps_campaign=camp.sk_nps_campaign
  LEFT JOIN justification AS just 
    ON ans.sk_nps_answer=just.sk_nps_answer
  LEFT JOIN offer AS offer 
    ON disp.sk_offer = offer.sk_offer
  LEFT JOIN dw_sale.dim_offer do 
    ON do.sk_offer = disp.sk_offer
  LEFT JOIN datalake_nps_quintocred.broker_contact_info as f 
    on regexp_extract(f.email, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9-]+(?=\.[a-zA-Z]{{2,}})', 0) = regexp_extract(disp.sk_nps_customer, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9-]+(?=\.[a-zA-Z]{{2,}})', 0)
    AND camp.sk_nps_campaign in ('quintoandar382','quintoandar493','quintoandar494','quintoandar495')
  LEFT JOIN visits 
    on visits.sk_buyer = disp.sk_user 
    and rank_visit = 1
  LEFT JOIN listings 
    on listings.sk_owner = disp.sk_user 
    and rank_depublication = 1
  LEFT JOIN dw_public.dim_user AS user 
    ON disp.sk_user = user.sk_user
  LEFT JOIN dim_agent_region_max AS region 
    ON region.sk_agent=user.dados_agente_id 
    AND rank_ = 1
  LEFT JOIN dim_region AS region_ 
    ON region_.region_code = region.area
  LEFT JOIN dw_public.dim_user AS user_2 
    ON regexp_extract(disp.sk_nps_customer, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9-]+(?=\.[a-zA-Z]{{2,}})', 0) = regexp_extract(user_2.email, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9-]+(?=\.[a-zA-Z]{{2,}})', 0)
  LEFT JOIN dw_public.dim_user AS dim_user_last 
    ON dim_user_last.sk_user=user_2.sk_user
  LEFT JOIN dim_region AS dim_region_5 
    ON LOWER(dim_region_5.city_name) = LOWER(dim_user_last.cidade)
  LEFT JOIN dim_agent_region_max AS region2 
    ON region2.sk_agent=user_2.dados_agente_id 
    AND region2.rank_ = 1
  LEFT JOIN dim_region AS region_2 
    ON region_2.region_code = region2.area
  LEFT JOIN dw_velo.dim_velo_broker AS user_velo 
    ON user_velo.sk_broker = f.id_broker
  LEFT JOIN dim_region AS region_3 
    ON LOWER(region_3.city_name) = LOWER(user_velo.city)
  LEFT JOIN dim_region AS region_4 
    ON LOWER(region_4.city_name) = LOWER(disp.city)
  WHERE 
    disp.sk_nps_answer>0
    and camp.sk_nps_campaign in (
      'quintoandar249',--For Sale
      'quintoandar250',
      'quintoandar251',
      'quintoandar252',
      'quintoandar253',
      'quintoandar254',
      'quintoandar297',
      'quintoandar298',
      'quintoandar330',
      'quintoandar331',
      'quintoandar454',
      'quintoandar455',
      'quintoandar479',
      'quintoandar480',
      'quintoandar382',--QuintoCred
      'quintoandar493',
      'quintoandar494',
      'quintoandar495',
      'quintoandar25',--Partners
      'quintoandar90',
      'quintoandar187',
      'quintoandar188',
      'quintoandar363',
      'quintoandar488',
      'quintoandar485',
      'quintoandar97',
      'quintoandar95',
      'quintoandar406',--Navent
      'quintoandar407',
      'quintoandar408',
      'quintoandar409',
      'quintoandar410',
      'quintoandar411',
      'quintoandar412',
      'quintoandar460',
      'quintoandar435',
      'quintoandar437',
      'quintoandar439',
      'quintoandar441',
      'quintoandar443',
      'quintoandar445',
      'quintoandar447',
      'quintoandar464',
      'quintoandar436',
      'quintoandar438',
      'quintoandar440',
      'quintoandar442',
      'quintoandar444',
      'quintoandar446',
      'quintoandar448',
      'quintoandar463',
      'quintoandar364'
  )
    and disp.sk_answered_date >= CAST(DATE_FORMAT('{load_start_date}', 'yyyyMMdd') AS INT)
),
final_ as (
  SELECT
    CASE WHEN posted_at IS NULL THEN '' ELSE posted_at 
    END AS posted_at,
    CASE WHEN ts_sale_agreement_signed IS NULL THEN '' ELSE ts_sale_agreement_signed 
    END AS ts_sale_agreement_signed,
    CASE WHEN feedback_id IS NULL THEN '' ELSE feedback_id 
    END AS feedback_id,
    CASE WHEN author_id IS NULL THEN ''
      WHEN author_id = -1 THEN ''
      ELSE author_id 
    END AS author_id,
    CASE WHEN sk_offer IS NULL THEN '' ELSE sk_offer 
    END AS sk_offer,
    CASE WHEN (account_id IS NULL OR account_id LIKE '-1%') AND author_id IS NOT NULL AND author_id > 0
        THEN CAST(feedback_id AS VARCHAR(50)) || '_' || CAST(author_id AS VARCHAR(50))
        WHEN (account_id IS NULL OR account_id LIKE '-1%')
        THEN CAST(feedback_id AS VARCHAR(50))
      ELSE account_id
    END AS account_id,
    CASE WHEN campaing = 'Agents (SMS)' THEN 'Corretor FR'
      WHEN campaing = 'Agents - ForSale' THEN 'Corretor FS'
      WHEN campaing = 'Agents (SMS) - ForSale' THEN 'Corretor FS'
      WHEN campaing = 'Agents CIQ' THEN 'Corretor CIQ'
      WHEN campaing = 'Agents - Corretores Select' THEN 'Corretor Select'
      WHEN metric_group IS NULL THEN ''
      ELSE metric_group 
    END AS customer_type,
    CASE WHEN score IS NULL THEN '' ELSE score 
    END AS rating,
    CASE WHEN score_category IS NULL THEN '' ELSE score_category 
    END AS score_category,
    CASE WHEN financing_bank IS NULL THEN '' ELSE financing_bank 
    END AS financing_bank,
    CASE WHEN payment_method IS NULL THEN '' ELSE payment_method 
    END AS payment_method,
    CASE WHEN internal_vendors_flag IS NULL THEN '' ELSE internal_vendors_flag 
    END AS internal_vendors_flag,
    CASE WHEN SELLER_DILLIGENCE_STATUS IS NULL THEN '' ELSE SELLER_DILLIGENCE_STATUS 
    END AS share_risco,
    CASE WHEN campaing = 'Agents'
        OR campaing = 'Agents (SMS)' THEN 'NPS Agents FR'
      WHEN campaing = 'Agents (SMS) - ForSale'
        OR campaing = 'Agents - ForSale' THEN 'NPS Agents FS'
      WHEN campaing = 'Agents - Corretores Select' THEN 'NPS Agents Select'
      WHEN campaing = 'Agents CIQ' THEN 'NPS Agents CIQ'
      WHEN campaing = 'Parceiros de Campo' THEN 'NPS Parceiros de Campo'
      WHEN campaing = 'Vistoriadores' THEN 'NPS Vistoriadores'
      WHEN campaing = '[NEW] Buyer CCV Central - ForSale'
        OR campaing = '[NEW] Buyer CCV Central - ForSale (Whatsapp)'
        OR campaing = '[NEW] Buyer CCV Hub - ForSale'
        OR campaing = '[NEW] Buyer CCV Hub - ForSale (Whatsapp)' THEN 'NPS CCV'
      WHEN campaing = '[NEW] Lost Buyer Proposals - ForSale'
        OR campaing = '[NEW] Lost Buyer Proposals - ForSale (SMS)' THEN 'NPS Lost Proposal FS'
      WHEN campaing = '[NEW] Lost Buyer Visits - ForSale'
        OR campaing = '[NEW] Lost Buyer Visits - ForSale (SMS)' THEN 'NPS Lost Visits FS'
      WHEN campaing = '[NEW] Seller (Unpublished) - ForSale'
        OR campaing = '[NEW] Seller (Unpublished) - ForSale (SMS)' THEN 'NPS Lost Unpublished FS'
      WHEN campaing = '[NEW] Seller CCV Central - ForSale'
        OR campaing = '[NEW] Seller CCV Central - ForSale (Whatsapp)'
        OR campaing = '[NEW] Seller CCV Hub - ForSale'
        OR campaing = '[NEW] Seller CCV Hub - ForSale (Whatsapp)' THEN 'NPS CCV'
      WHEN campaing = '[Navent] Current Publishers Adondevivir'
        OR campaing = '[Navent] Current Publishers Casa Mineira'
        OR campaing = '[Navent] Current Publishers Compreoaquille'
        OR campaing = '[Navent] Current Publishers Inmuebles24'
        OR campaing = '[Navent] Current Publishers Plusvalia'
        OR campaing = '[Navent] Current Publishers Urbania'
        OR campaing = '[Navent] Current Publishers imovelweb'
        OR campaing = '[Navent] Current Publishers Zonaprop' THEN 'NPS Current Publishers Navent'
      WHEN campaing = '[Navent] Lost Seekers Adondevivir'
        OR campaing = '[Navent] Lost Seekers Casa Mineira'
        OR campaing = '[Navent] Lost Seekers Compreoaquille'
        OR campaing = '[Navent] Lost Seekers Inmuebles24'
        OR campaing = '[Navent] Lost Seekers Plusvalia'
        OR campaing = '[Navent] Lost Seekers Urbania'
        OR campaing = '[Navent] Lost Seekers Zonaprop'
        OR campaing = '[Navent] Lost Seekers imovelweb' THEN 'NPS Lost Seekers Navent'
      WHEN campaing = '[Navent] True Seekers Adondevivir'
        OR campaing = '[Navent] True Seekers Casa Mineira'
        OR campaing = '[Navent] True Seekers Compreoaquille'
        OR campaing = '[Navent] True Seekers Imovelweb'
        OR campaing = '[Navent] True Seekers Inmuebles24'
        OR campaing = '[Navent] True Seekers Plusvalia'
        OR campaing = '[Navent] True Seekers Urbania'
        OR campaing = '[Navent] True Seekers Zonaprop' THEN 'NPS True Seekers Navent'
      WHEN campaing = '[Quintocred] Brokers Lost' THEN 'NPS Quintocred Inactive Brokers'
      WHEN campaing = '[Quintocred] Brokers Lost (Whastapp)' THEN 'NPS Quintocred Inactive Brokers'
      WHEN campaing = '[Quintocred] Brokers True' THEN 'NPS Quintocred True'
      WHEN campaing = '[Quintocred] Brokers True (Whastapp)' THEN 'NPS Quintocred True'
      WHEN campaing = 'Fotógrafos' THEN 'NPS Fotógrafos'
      WHEN campaing = 'Executivos Negociação/Associados' THEN 'NPS EN/EA'
      WHEN campaing IS NULL THEN '' ELSE campaing 
    END AS nome_campanha,
    CASE WHEN campaing LIKE '%Navent%' OR campaing LIKE '%Quintocred%' THEN ''
      WHEN city_name IS NULL THEN ''
      WHEN city_name = 'NÃO INFORMADO' THEN ''
      WHEN LOWER(city_name) = 'são paulo' THEN 'RMSP'
      WHEN LOWER(city_name) = 'hub - vila mariana' THEN 'RMSP'
      WHEN LOWER(city_name) = 'bh' THEN 'Belo Horizonte'
      WHEN LOWER(city_name) = 'minas gerais' THEN 'Belo Horizonte'
      WHEN LOWER(city_name) = 'poa' THEN 'Porto Alegre'
      WHEN LOWER(city_name) like '%porto alegre%' THEN 'Porto Alegre'
      WHEN LOWER(city_name) = 'rio grande do sul' THEN 'Porto Alegre'
      WHEN LOWER(city_name) = 'sãoleopoldo' THEN 'Porto Alegre'
      WHEN LOWER(city_name) like '%(rs)%' THEN 'Porto Alegre'
      WHEN LOWER(city_name) like '%(mg)%' THEN 'Belo Horizonte'
      WHEN LOWER(city_name) like '% mg%' THEN 'Belo Horizonte'
      WHEN LOWER(city_name) like '% sp%' THEN 'RMSP'
      WHEN LOWER(city_name) like '% rj%' THEN 'Rio de Janeiro'
    ELSE city_name END AS city_group,
    CASE WHEN country IS NULL THEN '' ELSE country 
    END AS country,
    CASE WHEN sk_nps_campaign IS NULL THEN '' ELSE sk_nps_campaign 
    END AS sk_nps_campaign,
    CASE
      WHEN NULLIF(comment, '') IS NULL
            AND NULLIF(justifications, '') IS NULL
            THEN NULL
      WHEN NULLIF(comment, '') IS NOT NULL
            AND NULLIF(justifications, '') IS NULL
            AND score <= 6
            THEN 'Motivo da minha insatisfação: ' || comment
      WHEN NULLIF(comment, '') IS NOT NULL
            AND NULLIF(justifications, '') IS NULL
            AND score IN (7,8)
            THEN 'Motivo da minha nota: ' || comment
      WHEN NULLIF(comment, '') IS NOT NULL
            AND NULLIF(justifications, '') IS NULL
            AND score >= 9
            THEN 'Motivo da minha satisfação: ' || comment
      WHEN NULLIF(comment, '') IS NULL
            AND NULLIF(justifications, '') IS NOT NULL
            AND score <= 6
            THEN 'Justificativa: ' || justifications
      WHEN NULLIF(comment, '') IS NULL
            AND NULLIF(justifications, '') IS NOT NULL
            AND score IN (7,8)
            THEN 'Justificativa: ' || justifications 
      WHEN NULLIF(comment, '') IS NULL
            AND NULLIF(justifications, '') IS NOT NULL
            AND score >= 9
            THEN 'Justificativa: ' || justifications
      WHEN NULLIF(comment, '') IS NOT NULL
            AND NULLIF(justifications, '') IS NOT NULL
            AND score <= 6
            THEN 'Motivo da minha insatisfação: ' || comment || ' Justificativa: ' || justifications
      WHEN NULLIF(comment, '') IS NOT NULL
            AND NULLIF(justifications, '') IS NOT NULL
            AND score IN (7,8)
            THEN 'Motivo da minha nota: ' || comment || ' Justificativa: ' || justifications
      WHEN NULLIF(comment, '') IS NOT NULL
            AND NULLIF(justifications, '') IS NOT NULL
            AND score >= 9
            THEN 'Motivo da minha satisfação: ' || comment || ' Justificativa: ' || justifications
      ELSE NULL
      END AS text
FROM final
)
SELECT
  date_format(posted_at, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  coalesce(date_format(ts_sale_agreement_signed, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''), '') AS ts_sale_agreement_signed,
  feedback_id,
  MAX(author_id) author_id,
  sk_offer,
  MAX(
    account_id ||
    CASE
        WHEN customer_type IS NOT NULL AND customer_type <> '' THEN '_' || REPLACE(customer_type, ' ', '_')
        ELSE ''
    END
  ) AS account_id,
  customer_type,
  CAST(rating AS INT) AS rating,
  score_category,
  financing_bank,
  payment_method,
  internal_vendors_flag,
  share_risco,
  nome_campanha AS nps_campanha,
  MAX(city_group) AS city_group,
  country,
  CASE WHEN text IS NULL THEN '' ELSE text END AS text,
  year(posted_at) AS year,
  month(posted_at) AS month,
  day(posted_at) AS day,
  NOW() AS ts_load
from final_
GROUP BY 
  posted_at,
  ts_sale_agreement_signed,
  feedback_id,
  sk_offer,
  customer_type,
  rating,
  score_category,
  financing_bank,
  payment_method,
  internal_vendors_flag,
  share_risco,
  nome_campanha,
  country,
  text
