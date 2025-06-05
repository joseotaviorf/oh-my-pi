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
 /*WHEN page ILIKE '%casamineira.com.br%' THEN 'casamineira'
 WHEN page ILIKE '%zapimoveis.com.br%' THEN 'zapimoveis'
 WHEN page ILIKE '%vivareal.com.br%' THEN 'vivareal'
 WHEN page ILIKE '%chavesnamao.com.br%' THEN 'chavesnamao'
 WHEN page ILIKE '%imoveis.mercadolivre.com.br%' THEN 'mercadolivre'*/
 WHEN page ILIKE '%inmuebles24.com%' THEN 'inmuebles24'
 WHEN page ILIKE '%vivanuncios.com.mx%' THEN 'vivanuncios'
 /*WHEN page ILIKE '%lamudi.com.mx%' THEN 'vivanuncios'
 WHEN page ILIKE '%propiedades.com%' THEN 'vivanuncios'
 WHEN page ILIKE '%inmuebles.mercadolibre.com.mx%' THEN 'mercadolibre_mx'
 WHEN page ILIKE '%easyaviso.com/mx%' THEN 'easyaviso'*/
 WHEN page ILIKE '%zonaprop.com.ar%' THEN 'zonaprop'
 WHEN page ILIKE '%urbania.pe%' THEN 'urbania'
 WHEN page ILIKE '%adondevivir.com%' THEN 'adondevivir.com'
 WHEN page ILIKE '%plusvalia.com%' THEN 'plusvalia.com'
 WHEN page ILIKE '%compreoalquile.com%' THEN 'compreoalquile'
 /*WHEN page ILIKE '%mudafy.com.ar%' THEN 'mudafy'*/
 --ELSE 'QuintoAndar'
 END AS domain,
 /*CASE
 WHEN RLIKE(page,'http://inmuebles24.com/') OR RLIKE(page,'https://www.imovelweb.com.br/')
 THEN SPLIT(REPLACE(REPLACE(page,'https://www.wimoveis.com.br/',''),'https://www.casamineira.com.br/', ''),'/')[0]
 END as slug,
 CASE
 WHEN RLIKE(page,'http://inmuebles24.com/') OR RLIKE(page,'https://www.imovelweb.com.br/')
 THEN SPLIT(REPLACE(REPLACE(page,'https://www.wimoveis.com.br/',''),'https://www.casamineira.com.br/', ''),'/')[1]
 END as subtitle_content,
 --REGEXP_EXTRACT(page, '.*ar\/imovel\/(.*\-brasil).*$') AS regiao_busca,
 --REGEXP_EXTRACT(page, 'quintoandar\.com\.br(.*)$') AS caminho_da_pagina,*/
 CASE
 WHEN RLIKE(LOWER(query),r'imovelweb|imovel web|webimoveis|imoveis web|imóvel web|imovel na web|imoveisweb|web imoveis|imoveweb|imovewweb|imovew|imvweb|imovewebs|imovel-web|imweb|web-imoveis|imoveis-web|imovelwebbr|imovelwebs|imovweb|imwebs|web-imovel|imovwebl|imove1web|imovelwebs|imovleweb|immovelweb') THEN TRUE
 WHEN RLIKE(LOWER(query),r'wimoveis|wimóveis|w imoveis|w imóveis|wiimoveis|winmoveis|wi imoveis') THEN TRUE
 WHEN RLIKE(LOWER(query),r'inmuebles24|inmuebles 24|inmueble 24|24 inmuebles|inmueble24') THEN TRUE
 WHEN RLIKE(LOWER(query),r'vivanuncios|viva anuncios|vivaanuncios') THEN TRUE
 WHEN RLIKE(LOWER(query),r'zonaprop|zona prop|zona pro|zonapro|zona propiedades|zonaprops|zonprop') THEN TRUE
 WHEN RLIKE(LOWER(query),r'urbania|urbanis|expourbania|urbani') THEN TRUE
 WHEN RLIKE(LOWER(query),r'adondevivir|a donde vivir|adonde vivir|donde vivir') THEN TRUE
 WHEN RLIKE(LOWER(query),r'plusvalia|plusvalía') THEN TRUE
 WHEN RLIKE(LOWER(query),r'compre o alquile|compreoalquile|compra o alquile|compre y alquile|compra y alquile|compra y alquila|compre o alquiler') THEN TRUE
 ELSE FALSE
 END AS is_branded
 FROM
 datalake_google_search_console_classified_clean.report_by_page_and_query
 WHERE
 DATE(dt_created) BETWEEN DATE('2025-04-22') AND DATE('2025-04-24')
 AND country IN ('bra', 'per', 'arg', 'mex', 'ecu', 'pan')
