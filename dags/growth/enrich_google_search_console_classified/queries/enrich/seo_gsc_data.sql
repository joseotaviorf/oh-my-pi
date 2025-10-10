WITH layer1 AS (
  SELECT
    site_url,
    device,
    page,
    query,
    country,
    dt_created,
    year,
    month,
    day,
    ctr,
    clicks,
    position,
    impressions,
    posimp,
    CASE
      WHEN page ILIKE '%imovelweb.com.br%' THEN 'imovelweb'
      WHEN page ILIKE '%wimoveis.com.br%' THEN 'wimoveis'
      WHEN page ILIKE '%casamineira.com.br%' THEN 'casamineira'
      WHEN page ILIKE '%inmuebles24.com%' THEN 'inmuebles24'
      WHEN page ILIKE '%vivanuncios.com.mx%' THEN 'vivanuncios'
      WHEN page ILIKE '%zonaprop.com.ar%' THEN 'zonaprop'
      WHEN page ILIKE '%urbania.pe%' THEN 'urbania'
      WHEN page ILIKE '%adondevivir.com%' THEN 'adondevivir.com'
      WHEN page ILIKE '%plusvalia.com%' THEN 'plusvalia.com'
      WHEN page ILIKE '%compreoalquile.com%' THEN 'compreoalquile'
    END AS domain,
    CASE
      WHEN RLIKE(LOWER(query),r'imovelweb|imovel web|webimoveis|imoveis web|imóvel web|imovel na web|imoveisweb|web imoveis|imoveweb|imovewweb|imovew|imvweb|imovewebs|imovel-web|imweb|web-imoveis|imoveis-web|imovelwebbr|imovelwebs|imovweb|imwebs|web-imovel|imovwebl|imove1web|imovelwebs|imovleweb|immovelweb') THEN TRUE
      WHEN RLIKE(LOWER(query),r'wimoveis|wimóveis|w imoveis|w imóveis|wiimoveis|winmoveis|wi imoveis') THEN TRUE
      WHEN RLIKE(LOWER(query),r'casamineira|casa mineira') THEN TRUE
      WHEN RLIKE(LOWER(query),r'inmuebles24|inmuebles 24|inmueble 24|24 inmuebles|inmueble24') THEN TRUE
      WHEN RLIKE(LOWER(query),r'vivanuncios|viva anuncios|vivaanuncios') THEN TRUE
      WHEN RLIKE(LOWER(query),r'zonaprop|zona prop|zona pro|zonapro|zona propiedades|zonaprops|zonprop') THEN TRUE
      WHEN RLIKE(LOWER(query),r'urbania|urbanis|expourbania|urbani') THEN TRUE
      WHEN RLIKE(LOWER(query),r'adondevivir|a donde vivir|adonde vivir|donde vivir') THEN TRUE
      WHEN RLIKE(LOWER(query),r'plusvalia|plusvalía') THEN TRUE
      WHEN RLIKE(LOWER(query),r'compre o alquile|compreoalquile|compra o alquile|compre y alquile|compra y alquile|compra y alquila|compre o alquiler') THEN TRUE
      ELSE FALSE
    END AS is_branded,
    CASE
      WHEN page LIKE '%com/desarrollos%' THEN 'Lancamentos'
      WHEN page LIKE '%ar/emprendimientos%' THEN 'Lancamentos'
      WHEN page LIKE '%pe/buscar/proyectos-propiedades%' THEN 'Lancamentos'
      WHEN page LIKE '%pe/proyectos%' THEN 'Lancamentos'
      WHEN page LIKE '%com/proyectos%' THEN 'Lancamentos'
      WHEN page LIKE '%br/desarrollos%' THEN 'Lancamentos'
      WHEN page LIKE '%mx/s-desarrollo%' THEN 'Lancamentos'
      --
      WHEN page LIKE '%br/imobiliarias%' THEN 'Inmobiliaria'
      WHEN page LIKE '%com/inmobiliarias%' THEN 'Inmobiliaria'
      WHEN page LIKE '%ar/inmobiliarias%' THEN 'Inmobiliaria'
      WHEN page LIKE '%pe/inmobiliarias%' THEN 'Inmobiliaria'
      WHEN page LIKE '%mx/inmobiliarias%' THEN 'Inmobiliaria'
      --
      WHEN page LIKE '%br/condominio/%' THEN 'Condominio'
      --
      WHEN page LIKE '%/noticias%' THEN 'Content'
      WHEN page LIKE '%/blog%' THEN 'Content'
      --
      WHEN page LIKE '%www.zonaprop.com.ar/' THEN 'Home'
      WHEN page LIKE '%www.imovelweb.com.br/' THEN 'Home'
      WHEN page LIKE '%www.wimoveis.com.br/' THEN 'Home'
      WHEN page LIKE '%www.inmuebles24.com/' THEN 'Home'
      WHEN page LIKE '%urbania.pe/' THEN 'Home'
      WHEN page LIKE '%www.adondevivir.com/' THEN 'Home'
      WHEN page LIKE '%www.compreoalquile.com/' THEN 'Home'
      WHEN page LIKE '%www.casamineira.com.br/' THEN 'Home'
      WHEN page LIKE '%www.plusvalia.com/' THEN 'Home'
      WHEN page LIKE '%www.vivanuncios.com.mx/' THEN 'Home'
      --
      WHEN page LIKE '%www.zonaprop.com.ar%' THEN 'Transactional'
      WHEN page LIKE '%www.imovelweb.com.br%' THEN 'Transactional'
      WHEN page LIKE '%www.wimoveis.com.br%' THEN 'Transactional'
      WHEN page LIKE '%www.inmuebles24.com%' THEN 'Transactional'
      WHEN page LIKE '%urbania.pe%' THEN 'Transactional'
      WHEN page LIKE '%www.adondevivir.com%' THEN 'Transactional'
      WHEN page LIKE '%www.compreoalquile.com%' THEN 'Transactional'
      WHEN page LIKE '%www.casamineira.com.br%' THEN 'Transactional'
      WHEN page LIKE '%www.plusvalia.com%' THEN 'Transactional'
      WHEN page LIKE '%www.vivanuncios.com.mx%' THEN 'Transactional'
      --
      ELSE 'Other'
    END AS struct,
    CASE 
      WHEN page LIKE "%imovelweb.com.br/%aluguel%" THEN "Rent"
      WHEN page LIKE "%imovelweb.com.br/%venda%" THEN "Sale"
      WHEN page LIKE "%imovelweb.com.br/%temporada%" THEN "Short term rent"
      WHEN page LIKE "%imovelweb.com.br/%lancamentos%" THEN "Sale primary market"
      WHEN page LIKE "%imovelweb.com.br/%leilao%" THEN "Auction"
      --
      WHEN page LIKE "%wimoveis.com.br/%aluguel%" THEN "Rent"
      WHEN page LIKE "%wimoveis.com.br/%venda%" THEN "Sale"
      WHEN page LIKE "%wimoveis.com.br/%temporada%" THEN "Short term rent"
      WHEN page LIKE "%wimoveis.com.br/%lancamento%" THEN "Sale primary market"
      WHEN page LIKE "%wimoveis.com.br/%leilao%" THEN "Auction"
      --
      WHEN page LIKE "%casamineira.com.br/aluguel%" THEN "Rent"
      WHEN page LIKE "%casamineira.com.br/venda%" THEN "Sale"
      WHEN page LIKE "%casamineira.com.br/lancamento%" THEN "Sale primary market"
      --
      WHEN page LIKE "%inmuebles24.com/%en-renta%" THEN "Rent"
      WHEN page LIKE "%inmuebles24.com/%comercializa-remates%" THEN "Auction"
      WHEN page LIKE "%inmuebles24.com/%en-venta%" THEN "Sale"
      WHEN page LIKE "%inmuebles24.com/%en-temporal-vacacional%" THEN "Short term rent"
      WHEN page LIKE "%inmuebles24.com/%desarrollos%" THEN "Sale primary market"
      WHEN page LIKE "%inmuebles24.com/%en-traspaso%" THEN "Transfer"
      --
      WHEN page LIKE "%vivanuncios.com.mx/%renta%" THEN "Rent"
      WHEN page LIKE "%vivanuncios.com.mx/%venta%" THEN "Sale"
      WHEN page LIKE "%vivanuncios.com.mx/%remate%" THEN "Auction"
      WHEN page LIKE "%vivanuncios.com.mx/%renta-vacacional%" THEN "Short term rent"
      WHEN page LIKE "%vivanuncios.com.mx/%desarrollo%" THEN "Sale primary market"
      WHEN page LIKE "%vivanuncios.com.mx/%traspaso%" THEN "Transfer"
      --
      WHEN page LIKE "%zonaprop.com.ar/%alquiler%" THEN "Rent"
      WHEN page LIKE "%zonaprop.com.ar/%venta%" THEN "Sale"
      WHEN page LIKE "%zonaprop.com.ar/%temporal%" THEN "Short term rent"
      WHEN page LIKE "%zonaprop.com.ar/%emprendimientos%" THEN "Sale primary market"
      --
      WHEN page LIKE "%urbania.pe/%alquiler-temporal%" THEN "Short term rent"
      WHEN page LIKE "%urbania.pe/%alquiler%" THEN "Rent"
      WHEN page LIKE "%urbania.pe/%venta%" THEN "Sale"
      WHEN page LIKE "%urbania.pe/%proyectos%" THEN "Sale primary market"
      WHEN page LIKE "%urbania.pe/%traspaso%" THEN "Transfer"
      --
      WHEN page LIKE "%adondevivir.com/%alquiler-temporal%" THEN "Short term rent"
      WHEN page LIKE "%adondevivir.com/%alquiler%" THEN "Rent"
      WHEN page LIKE "%adondevivir.com/%venta%" THEN "Sale"
      WHEN page LIKE "%adondevivir.com/%proyectos%" THEN "Sale primary market"
      WHEN page LIKE "%adondevivir.com/%traspaso%" THEN "Transfer"
      --
      WHEN page LIKE "%plusvalia.com/%alquiler%" THEN "Rent"
      WHEN page LIKE "%plusvalia.com/%venta%" THEN "Sale"
      WHEN page LIKE "%plusvalia.com/%temporal-vacacional%" THEN "Short term rent"
      WHEN page LIKE "%plusvalia.com/%proyecto%" THEN "Sale primary market"
      WHEN page LIKE "%plusvalia.com/%traspaso%" THEN "Transfer"
      --
      WHEN page LIKE "%compreoalquile.com/%alquiler%" THEN "Rent"
      WHEN page LIKE "%compreoalquile.com/%venta%" THEN "Sale"
      WHEN page LIKE "%compreoalquile.com/%temporal%" THEN "Short term rent"
      WHEN page LIKE "%compreoalquile.com/%desarrollos%" THEN "Sale primary market"
      WHEN page LIKE "%compreoalquile.com/%traspaso%" THEN "Transfer"
      --
      ELSE "N/A" 
    END AS business_context
  FROM
    datalake_google_search_console_classified_clean.report_by_page_and_query
  WHERE
    dt_created BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND country IN ('bra', 'per', 'arg', 'mex', 'ecu', 'pan')
)
SELECT
  query,
  site_url,
  device,
  page,
  country,
  ctr,
  clicks,
  position,
  impressions,
  posimp,
  domain,
  struct,
  business_context,
  is_branded,
  dt_created,
  year,
  month,
  day
FROM
  layer1
