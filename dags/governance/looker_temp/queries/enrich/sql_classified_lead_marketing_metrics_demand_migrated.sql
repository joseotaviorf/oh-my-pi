WITH house_listing AS (
  SELECT DISTINCT
    r.city_group,
    CAST(hl.id AS INT) AS id_house
  FROM datalake_ebdb_listing.house AS hl
  LEFT JOIN dw_public.dim_region AS r
    ON hl.id_region = r.id
), classified AS (
  SELECT DISTINCT
    AT_TIMEZONE(lc.ts_received, 'America/Sao_Paulo') AS ts_event,
    CAST(AT_TIMEZONE(lc.ts_received, 'America/Sao_Paulo') AS DATE) AS dt_event,
    lc.business_context AS campaign_context,
    'Tenants PWA' AS mkt_origin,
    'Paid Acquisition' AS mkt_channel,
    'Online Classifieds' AS mkt_medium,
    lc.origin_partner AS utm_source,
    CASE
      WHEN lc.origin_partner IN ('Zap', 'ZAP', 'GRUPO_ZAP', 'VIVA_REAL', 'VivaReal')
      THEN 'Grupo Zap'
      WHEN lc.origin_partner IN ('Zap', 'ZAP')
      THEN 'Zap Imóveis'
      WHEN lc.origin_partner IN ('FACEBOOK_MARKETPLACE', 'Facebook')
      THEN 'Facebook'
      WHEN lc.origin_partner IN ('MERCADO_LIVRE', 'MercadoLivre')
      THEN 'Mercado Livre'
      WHEN lc.origin_partner IN ('IMOVEL_WEB', 'ImovelWeb', 'IMOVEL_WEB_PREMIER')
      THEN 'Imovelweb'
      WHEN lc.origin_partner IN ('WImoveis')
      THEN 'WImoveis'
      WHEN lc.origin_partner IN ('CASA_MINEIRA')
      THEN 'Casa Mineira'
      WHEN lc.origin_partner IN ('OLX')
      THEN 'OLX'
      WHEN lc.origin_partner IN ('Storia')
      THEN 'Storia'
      WHEN lc.origin_partner IN ('Oba')
      THEN 'Oba'
      WHEN lc.origin_partner IN ('123i', 'UM_DOIS_TRES_I')
      THEN '123i'
      WHEN lc.origin_partner IN ('CHAVES_NA_MAO')
      THEN 'Chave na Mão'
      ELSE lc.origin_partner
    END AS mkt_source,
    CAST(lc.id_property AS INT) AS id_house,
    lc.publication_type AS classified_publication_type,
    CASE
      WHEN lc.user_message IN ('Viu telefone.')
      THEN 'viu_telefone'
      ELSE 'formulario'
    END AS `message_type`,
    COALESCE(CAST(lc.user_email AS STRING), CAST(lc.user_phone_number AS STRING)) AS sk_lead,
    ROW_NUMBER() OVER (PARTITION BY COALESCE(CAST(lc.user_email AS STRING), CAST(lc.user_phone_number AS STRING)) ORDER BY lc.ts_received ASC NULLS LAST) AS lead_order,
    CASE
      WHEN NOT lc.user_phone_number IS NULL
      THEN 'com_telefone'
      ELSE 'sem_telefone'
    END AS `user_with_phone`,
    CASE WHEN lre.id IS NULL THEN 'sem_reply_email' ELSE 'com_reply_email' END AS `reply_email`,
    CASE
      WHEN (
        lrw.id IS NULL AND NOT lc.user_phone_number IS NULL
      )
      THEN 'sem_reply_whatsapp'
      WHEN lc.user_phone_number IS NULL
      THEN 'nao_deu_telefone'
      ELSE 'com_reply_whatsapp'
    END AS `reply_whatsapp`,
    CASE WHEN (
      NOT lre.id IS NULL OR NOT lrw.id IS NULL
    ) THEN 1 ELSE 0 END AS `reply`
  FROM datalake_classified_leads_clean.lead_contact AS lc
  LEFT JOIN datalake_classified_leads_clean.lead_reply_email AS lre
    ON lre.id_lead = lc.id
  LEFT JOIN datalake_classified_leads_clean.lead_reply_whatsapp AS lrw
    ON lrw.id_lead = lc.id
  WHERE
    lc.ts_received >= DATE('2021-10-01')
)
SELECT DISTINCT
  ts_event,
  dt_event,
  campaign_context,
  mkt_origin,
  mkt_channel,
  mkt_medium,
  utm_source,
  mkt_source,
  c.id_house,
  hl.city_group,
  classified_publication_type,
  message_type,
  sk_lead,
  lead_order,
  CAST(u.sk_user AS INT) AS sk_client,
  user_with_phone,
  reply_email,
  reply_whatsapp,
  reply
FROM classified AS c
LEFT JOIN house_listing AS hl
  ON c.id_house = hl.id_house
LEFT JOIN dw_public.dim_user AS u
  ON u.email = c.sk_lead