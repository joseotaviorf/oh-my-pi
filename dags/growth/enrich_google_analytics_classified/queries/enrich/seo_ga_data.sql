SELECT
  gac.event_timestamp_utc,
  gac.event_date,
  gac.site,
  gac.property_id,
  gac.platform,
  gac.stream_id,
  gac.city,
  gac.country,
  gac.region,
  gac.hostname,
  gac.device,
  gac.user_id_custom,
  gac.user_pseudo_id,
  gac.unique_session_id,
  gac.ga_session_number,
  gac.event_name,
  gac.lead_type,
  gac.lead_id,
  gac.page_location,
  gac.site_section,
  gac.operation_type,
  gac.session_source,
  gac.session_medium,
  gac.session_campaign_id,
  gac.session_campaign_name,
  gac.session_ad_content,
  gac.session_ad_term,
  gac.session_source_platform,
  gac.session_creative_format,
  gac.session_marketing_tactic,
  gac.session_gads_ad_group_id,
  gac.session_gads_ad_group_name,
  gac.event_campaign_id,
  gac.event_campaign_name,
  gac.event_source,
  gac.event_medium,
  gac.event_term,
  gac.event_content,
  gac.event_source_platform,
  gac.event_creative_format,
  gac.event_marketing_tactic,
  gac.event_gclid,
  gac.session_ga4_default_channel_group,
  gac.last_update,
  gac.total_events,
  CASE
    WHEN RLIKE(LOWER(gac.page_location),r'imovelweb|imovel web|webimoveis|imoveis web|imóvel web|imovel na web|imoveisweb|web imoveis|imoveweb|imovewweb|imovew|imvweb|imovewebs|imovel-web|imweb|web-imoveis|imoveis-web|imovelwebbr|imovelwebs|imovweb|imwebs|web-imovel|imovwebl|imove1web|imovelwebs|imovleweb|immovelweb') THEN TRUE
    WHEN RLIKE(LOWER(gac.page_location),r'wimoveis|wimóveis|w imoveis|w imóveis|wiimoveis|winmoveis|wi imoveis') THEN TRUE
    WHEN RLIKE(LOWER(gac.page_location),r'inmuebles24|inmuebles 24|inmueble 24|24 inmuebles|inmueble24') THEN TRUE
    WHEN RLIKE(LOWER(gac.page_location),r'vivanuncios|viva anuncios|vivaanuncios') THEN TRUE
    WHEN RLIKE(LOWER(gac.page_location),r'zonaprop|zona prop|zona pro|zonapro|zona propiedades|zonaprops|zonprop') THEN TRUE
    WHEN RLIKE(LOWER(gac.page_location),r'urbania|urbanis|expourbania|urbani') THEN TRUE
    WHEN RLIKE(LOWER(gac.page_location),r'adondevivir|a donde vivir|adonde vivir|donde vivir') THEN TRUE
    WHEN RLIKE(LOWER(gac.page_location),r'plusvalia|plusvalía') THEN TRUE
    WHEN RLIKE(LOWER(gac.page_location),r'compre o alquile|compreoalquile|compra o alquile|compre y alquile|compra y alquile|compra y alquila|compre o alquiler') THEN TRUE
    ELSE FALSE
  END AS is_branded,
  CASE
    WHEN gac.page_location LIKE '%com/desarrollos%' THEN 'Lancamentos'
    WHEN gac.page_location LIKE '%ar/emprendimientos%' THEN 'Lancamentos'
    WHEN gac.page_location LIKE '%pe/buscar/proyectos-propiedades%' THEN 'Lancamentos'
    WHEN gac.page_location LIKE '%pe/proyectos%' THEN 'Lancamentos'
    WHEN gac.page_location LIKE '%br/desarrollos%' THEN 'Lancamentos'
    WHEN gac.page_location LIKE '%br/imobiliarias%' THEN 'Inmobiliaria'
    WHEN gac.page_location LIKE '%br/imobiliarias%' THEN 'Inmobiliaria'
    WHEN gac.page_location LIKE '%com/inmobiliarias%' THEN 'Inmobiliaria'
    WHEN gac.page_location LIKE '%ar/inmobiliarias%' THEN 'Inmobiliaria'
    WHEN gac.page_location LIKE '%pe/inmobiliarias%' THEN 'Inmobiliaria'
    WHEN gac.page_location LIKE '%br/condominio/%' THEN 'Condominio'
    WHEN gac.page_location LIKE 'https://www.zonaprop.com.ar/' THEN 'Home'
    WHEN gac.page_location LIKE 'https://www.imovelweb.com.br/' THEN 'Home'
    WHEN gac.page_location LIKE 'https://www.wimoveis.com.br/' THEN 'Home'
    WHEN gac.page_location LIKE 'https://www.inmuebles24.com/' THEN 'Home'
    WHEN gac.page_location LIKE 'https://www.urbania.pe/' THEN 'Home'
    WHEN gac.page_location LIKE 'https://www.adondevivir.pe/' THEN 'Home'
    WHEN gac.page_location LIKE 'https://www.compreoalquile.com/' THEN 'Home'
    WHEN gac.page_location LIKE 'https://www.casamineira.com/' THEN 'Home'
    WHEN gac.page_location LIKE 'http://www.zonaprop.com.ar/' THEN 'Home'
    WHEN gac.page_location LIKE 'http://www.imovelweb.com.br/' THEN 'Home'
    WHEN gac.page_location LIKE 'http://www.wimoveis.com.br/' THEN 'Home'
    WHEN gac.page_location LIKE 'http://www.inmuebles24.com/' THEN 'Home'
    WHEN gac.page_location LIKE 'http://www.urbania.pe/' THEN 'Home'
    WHEN gac.page_location LIKE 'http://www.adondevivir.pe/' THEN 'Home'
    WHEN gac.page_location LIKE 'http://www.compreoalquile.com/' THEN 'Home'
    WHEN gac.page_location LIKE 'http://www.casamineira.com/' THEN 'Home'
    WHEN gac.page_location LIKE 'https://www.zonaprop.com.ar/%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'https://www.imovelweb.com.br%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'https://www.wimoveis.com.br%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'https://www.inmuebles24.com%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'https://www.urbania.pe%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'https://www.adondevivir.pe%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'https://www.compreoalquile.com%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'https://www.casamineira.com%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'http://www.zonaprop.com.ar/%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'http://www.imovelweb.com.br%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'http://www.wimoveis.com.br%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'http://www.inmuebles24.com%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'http://www.urbania.pe%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'http://www.adondevivir.pe%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'http://www.compreoalquile.com%' THEN 'Transactional'
    WHEN gac.page_location LIKE 'http://www.casamineira.com%' THEN 'Transactional'
    WHEN gac.page_location LIKE '%/zonaprop.com.ar/%' THEN 'Content'
    WHEN gac.page_location LIKE '%/imovelweb.com.br/%' THEN 'Content'
    WHEN gac.page_location LIKE '%/wimoveis.com.br/%' THEN 'Content'
    WHEN gac.page_location LIKE '%/inmuebles24.com/%' THEN 'Content'
    WHEN gac.page_location LIKE '%/urbania.pe/%' THEN 'Content'
    WHEN gac.page_location LIKE '%/adondevivir.pe/%' THEN 'Content'
    WHEN gac.page_location LIKE '%/compreoalquile.com/%' THEN 'Content'
    WHEN gac.page_location LIKE '%/casamineira.com/%' THEN 'Content'
    ELSE 'Other'
  END AS structPage
FROM
  datalake_google_analytics_classified_clean.google_analytics_classified as gac
WHERE
  DATE(event_date) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
