SELECT
  id_property,
  id_stream,
  id_user_custom,
  id_user_pseudo,
  id_session,
  id_session_campaign,
  id_session_gads_ad_group,
  id_event_campaign,
  id_lead,
  platform,
  ga_number,
  site_section,
  city,
  country,
  region,
  hostname,
  device,
  lead_type,
  page_location,
  operation_type,
  ses_src,
  ses_medium,
  ses_cmp_name,
  ses_ad_content,
  ses_ad_term,
  ses_src_platform,
  ses_creative_format,
  ses_mkt_tactic,
  ses_gads_ad_grp_name,
  ev_name,
  ev_cmp_name,
  ev_src,
  ev_medium,
  ev_term,
  ev_content,
  ev_src_platform,
  ev_creative_format,
  ev_mkt_tactics,
  ev_gclid,
  ses_ga4_def_channel_grp,
  ev_total,
  CASE
    WHEN RLIKE(LOWER(page_location),r'imovelweb|imovel web|webimoveis|imoveis web|imóvel web|imovel na web|imoveisweb|web imoveis|imoveweb|imovewweb|imovew|imvweb|imovewebs|imovel-web|imweb|web-imoveis|imoveis-web|imovelwebbr|imovelwebs|imovweb|imwebs|web-imovel|imovwebl|imove1web|imovelwebs|imovleweb|immovelweb') THEN TRUE
    WHEN RLIKE(LOWER(page_location),r'wimoveis|wimóveis|w imoveis|w imóveis|wiimoveis|winmoveis|wi imoveis') THEN TRUE
    WHEN RLIKE(LOWER(page_location),r'inmuebles24|inmuebles 24|inmueble 24|24 inmuebles|inmueble24') THEN TRUE
    WHEN RLIKE(LOWER(page_location),r'vivanuncios|viva anuncios|vivaanuncios') THEN TRUE
    WHEN RLIKE(LOWER(page_location),r'zonaprop|zona prop|zona pro|zonapro|zona propiedades|zonaprops|zonprop') THEN TRUE
    WHEN RLIKE(LOWER(page_location),r'urbania|urbanis|expourbania|urbani') THEN TRUE
    WHEN RLIKE(LOWER(page_location),r'adondevivir|a donde vivir|adonde vivir|donde vivir') THEN TRUE
    WHEN RLIKE(LOWER(page_location),r'plusvalia|plusvalía') THEN TRUE
    WHEN RLIKE(LOWER(page_location),r'compre o alquile|compreoalquile|compra o alquile|compre y alquile|compra y alquile|compra y alquila|compre o alquiler') THEN TRUE
    ELSE FALSE
  END AS is_branded,
  CASE
    WHEN page_location LIKE '%com/desarrollos%' THEN 'Lancamentos'
    WHEN page_location LIKE '%ar/emprendimientos%' THEN 'Lancamentos'
    WHEN page_location LIKE '%pe/buscar/proyectos-propiedades%' THEN 'Lancamentos'
    WHEN page_location LIKE '%pe/proyectos%' THEN 'Lancamentos'
    WHEN page_location LIKE '%br/desarrollos%' THEN 'Lancamentos'
    WHEN page_location LIKE '%br/imobiliarias%' THEN 'Inmobiliaria'
    WHEN page_location LIKE '%com/inmobiliarias%' THEN 'Inmobiliaria'
    WHEN page_location LIKE '%ar/inmobiliarias%' THEN 'Inmobiliaria'
    WHEN page_location LIKE '%pe/inmobiliarias%' THEN 'Inmobiliaria'
    WHEN page_location LIKE '%br/condominio/%' THEN 'Condominio'
    WHEN page_location LIKE 'https://www.zonaprop.com.ar/' THEN 'Home'
    WHEN page_location LIKE 'https://www.imovelweb.com.br/' THEN 'Home'
    WHEN page_location LIKE 'https://www.wimoveis.com.br/' THEN 'Home'
    WHEN page_location LIKE 'https://www.inmuebles24.com/' THEN 'Home'
    WHEN page_location LIKE 'https://www.urbania.pe/' THEN 'Home'
    WHEN page_location LIKE 'https://www.adondevivir.pe/' THEN 'Home'
    WHEN page_location LIKE 'https://www.compreoalquile.com/' THEN 'Home'
    WHEN page_location LIKE 'https://www.casamineira.com/' THEN 'Home'
    WHEN page_location LIKE 'http://www.zonaprop.com.ar/' THEN 'Home'
    WHEN page_location LIKE 'http://www.imovelweb.com.br/' THEN 'Home'
    WHEN page_location LIKE 'http://www.wimoveis.com.br/' THEN 'Home'
    WHEN page_location LIKE 'http://www.inmuebles24.com/' THEN 'Home'
    WHEN page_location LIKE 'http://www.urbania.pe/' THEN 'Home'
    WHEN page_location LIKE 'http://www.adondevivir.pe/' THEN 'Home'
    WHEN page_location LIKE 'http://www.compreoalquile.com/' THEN 'Home'
    WHEN page_location LIKE 'http://www.casamineira.com/' THEN 'Home'
    WHEN page_location LIKE 'https://www.zonaprop.com.ar/%' THEN 'Transactional'
    WHEN page_location LIKE 'https://www.imovelweb.com.br%' THEN 'Transactional'
    WHEN page_location LIKE 'https://www.wimoveis.com.br%' THEN 'Transactional'
    WHEN page_location LIKE 'https://www.inmuebles24.com%' THEN 'Transactional'
    WHEN page_location LIKE 'https://www.urbania.pe%' THEN 'Transactional'
    WHEN page_location LIKE 'https://www.adondevivir.pe%' THEN 'Transactional'
    WHEN page_location LIKE 'https://www.compreoalquile.com%' THEN 'Transactional'
    WHEN page_location LIKE 'https://www.casamineira.com%' THEN 'Transactional'
    WHEN page_location LIKE 'http://www.zonaprop.com.ar/%' THEN 'Transactional'
    WHEN page_location LIKE 'http://www.imovelweb.com.br%' THEN 'Transactional'
    WHEN page_location LIKE 'http://www.wimoveis.com.br%' THEN 'Transactional'
    WHEN page_location LIKE 'http://www.inmuebles24.com%' THEN 'Transactional'
    WHEN page_location LIKE 'http://www.urbania.pe%' THEN 'Transactional'
    WHEN page_location LIKE 'http://www.adondevivir.pe%' THEN 'Transactional'
    WHEN page_location LIKE 'http://www.compreoalquile.com%' THEN 'Transactional'
    WHEN page_location LIKE 'http://www.casamineira.com%' THEN 'Transactional'
    WHEN page_location LIKE '%/zonaprop.com.ar/%' THEN 'Content'
    WHEN page_location LIKE '%/imovelweb.com.br/%' THEN 'Content'
    WHEN page_location LIKE '%/wimoveis.com.br/%' THEN 'Content'
    WHEN page_location LIKE '%/inmuebles24.com/%' THEN 'Content'
    WHEN page_location LIKE '%/urbania.pe/%' THEN 'Content'
    WHEN page_location LIKE '%/adondevivir.pe/%' THEN 'Content'
    WHEN page_location LIKE '%/compreoalquile.com/%' THEN 'Content'
    WHEN page_location LIKE '%/casamineira.com/%' THEN 'Content'
    ELSE 'Other'
  END AS structPage,
  ts_event_timestamp_utc,
  ts_event,
  ts_last_update,
  year,
  month,
  day
FROM
  datalake_google_analytics_classified_clean.google_analytics_classified
WHERE
  DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
