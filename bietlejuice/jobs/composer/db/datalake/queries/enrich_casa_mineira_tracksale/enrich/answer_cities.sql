WITH answer_cities AS (
     SELECT
          atg.id_answer,
          COALESCE(eh.city, (CASE WHEN atg.tag_name = 'Cidade' THEN atg.tag_value END)) AS city
     FROM
          datalake_casa_mineira_tracksale.answer_tags atg
     LEFT JOIN datalake_nps_answer_drivers.answer_drivers ad
          ON atg.id_answer = ad.id_answer
     LEFT JOIN datalake_ebdb_clean.booking eb 
          ON eb.id = ad.id_booking
     LEFT JOIN datalake_ebdb_clean.offer eo
          ON eo.id = (ad.id_offer_context - 2)/100.0
     LEFT JOIN datalake_firestore.sale_offer so
          ON so.id = ad.id_offer_context
     LEFT JOIN datalake_ebdb_clean.contract ec
          ON ec.id = ad.id_contract
     LEFT JOIN datalake_ebdb_listing.house_listing ehl
          ON ehl.id_house_listing = ad.id_house_listing
     LEFT JOIN datalake_ebdb_clean.house eh
          ON COALESCE(ehl.id_house, ec.id_house, eo.id_house, so.id_house, eb.id_house, ad.id_listing) = eh.id
     WHERE
          COALESCE(eh.city, (CASE WHEN atg.tag_name = 'Cidade' THEN atg.tag_value END)) IS NOT NULL
     GROUP BY 1,2
)
SELECT
     id_answer,
     CASE 
          WHEN RLIKE(city, '^[a-zA-Zà-úÀ-Ú]') = False THEN 'NÃO INFORMADO'
          WHEN LOWER(city) LIKE '%.%.%-%' THEN 'NÃO INFORMADO'
          WHEN LOWER(city) LIKE '%0%' THEN 'NÃO INFORMADO'
          WHEN LOWER(city) LIKE '%1%' THEN 'NÃO INFORMADO'
          WHEN LOWER(city) LIKE '%3%' THEN 'NÃO INFORMADO'
          WHEN LOWER(city) IN ('sp','sao paulo', 'sã£o paulo','são paulo - sp', 'su00e3o paulo') THEN 'SÃO PAULO'
          WHEN LOWER(city) LIKE ('%são paulo%') THEN 'SÃO PAULO'
          WHEN LOWER(city) IN ('rj') THEN 'RIO DE JANEIRO'
          WHEN LOWER(city) LIKE '%rio de janeiro%' THEN 'RIO DE JANEIRO'
          WHEN LOWER(city) IN ('mg') THEN 'MINAS GERAIS'
          WHEN LOWER(city) IN ('rs', 'rio grande') THEN 'RIO GRANDE DO SUL'
          WHEN LOWER(city) IN ('pr') THEN 'PARANA'
          WHEN LOWER(city) IN ('bsb', 'brasilia' ) THEN 'BRASÍLIA'
          WHEN LOWER(city) LIKE '%abc%' THEN 'RMSP'
          WHEN LOWER(city) IN ('grande são paulo') THEN 'RMSP'
          WHEN LOWER(city) IN ('osasco/barueri', 'barueri', 'bareuri') THEN 'BARUERI'
          WHEN LOWER(city) IN ('taubaté33') THEN 'TAUBATÉ'
          WHEN LOWER(city) IN ('santo andre', 'santo andru00e9') THEN 'SANTO ANDRÉ'
          WHEN LOWER(city) IN ('valinhos - sp', 'valinhos-sp' ) THEN 'VALINHOS'
          WHEN LOWER(city) IN ('santana de parnaiba') THEN 'SANTANA DE PARNAÍBA'
          WHEN LOWER(city) IN ('sao bernardo do campo', 'sao bernardo do campo - sp', 'são bernardo do campo - sp', 'su00e3o bernardo do campo') THEN 'SÃO BERNARDO DO CAMPO'
          WHEN LOWER(city) IN ('su00e3o caetano do sul') THEN 'SÃO CAETANO DO SUL'    
          WHEN LOWER(city) IN ('são gonçalo - rj') THEN 'SÃO GONÇALO'
          WHEN LOWER(city) IN ('niteroi') THEN 'NITERÓI'
          WHEN LOWER(city) IN ('goiania') THEN 'GOIÂNIA'
          WHEN LOWER(city) IN ('go') THEN 'GOIÁS'
          WHEN LOWER(city) IN ('camp') THEN 'CAMPINAS'
          WHEN LOWER(city) IN ('porto alegre, florianópolis') THEN 'PORTO ALEGRE'
          WHEN LOWER(city) IN ('sc') THEN 'SANTA CATARINA'
          WHEN LOWER(city) IN ('florianopolis') THEN 'FLORIANÓPOLIS'
          WHEN LOWER(city) IN ('rescisão','negociação','#n/a', 'contrato','verificar', '-', 'way', ' ') THEN 'NÃO INFORMADO'
          ELSE RTRIM(UPPER(city))
     END AS city
FROM 
     answer_cities