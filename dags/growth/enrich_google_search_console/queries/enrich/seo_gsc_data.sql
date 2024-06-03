WITH
layer1 AS (
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
            WHEN page ILIKE '%proprietario.quintoandar%' THEN 'Supply'
            WHEN page ILIKE '%meulugar.quintoandar%' THEN 'Content'
            WHEN page ILIKE '%conteudos.quintoandar%' THEN 'Content'
            WHEN page ILIKE '%help.quintoandar%' THEN 'Help'
            ELSE 'QuintoAndar'
        END AS domain,
          CASE 
            WHEN RLIKE(page,'https://conteudos.quintoandar.com.br/') OR RLIKE(page,'https://meulugar.quintoandar.com.br/')
            THEN SPLIT(REPLACE(REPLACE(page,'https://conteudos.quintoandar.com.br/',''),'https://meulugar.quintoandar.com.br/', ''),'/')[0]
          END as slug,
          CASE 
            WHEN RLIKE(page,'https://conteudos.quintoandar.com.br/') OR RLIKE(page,'https://meulugar.quintoandar.com.br/')
            THEN SPLIT(REPLACE(REPLACE(page,'https://conteudos.quintoandar.com.br/',''),'https://meulugar.quintoandar.com.br/', ''),'/')[1]
          END as subtitle_content,
        REGEXP_EXTRACT(page, '.*ar\/imovel\/(.*\-brasil).*$') AS regiao_busca,
        REGEXP_EXTRACT(page, 'quintoandar\.com\.br(.*)$') AS caminho_da_pagina,
        CASE 
          WHEN RLIKE(LOWER(query),r'5o andar|indica ai|quin to|quarto andar|5 a|5 andar|5A|quimto andar|quinto|quinto amdar|quinto anda|quinto andar|quintoandar|5 andas|5 abdar|5 adar|5 amdar|5 anadr|5 anar|5 anda|5 andad|5 andae|5 andart|5 andas|5 andat|5 ander|5 andr|5 andra|5 andro|5 andsr|5 ansar|4anda|5 ndar|5 qndar|5 sndar|4 andar|5°andar|5amdar|5and|5anda|5andae|5andar|5andat|5andsr|5ansar|5ºandar|5oandar') THEN TRUE
          ELSE FALSE
        END AS is_branded,
        CASE
            WHEN REGEXP_LIKE(page, '.*alvorada-rs.*') THEN 'alvorada-rs'
            WHEN REGEXP_LIKE(page, '.*americana-sp.*') THEN 'americana-sp'
            WHEN REGEXP_LIKE(page, '.*aparecida-de-goiania-go.*') THEN 'aparecida-de-goiania-go'
            WHEN REGEXP_LIKE(page, '.*barueri-sp.*') THEN 'barueri-sp'
            WHEN REGEXP_LIKE(page, '.*belford-roxo-rj.*') THEN 'belford-roxo-rj'
            WHEN REGEXP_LIKE(page, '(.*belo-horizonte-mg.*)|(.*belo-horizonte-bh.*)|(.*belo-horizonte.*)') THEN 'belo-horizonte-mg'
            WHEN REGEXP_LIKE(page, '.*belem-pa.*') THEN 'belem-pa'
            WHEN REGEXP_LIKE(page, '.*betim-mg.*') THEN 'betim-mg'
            WHEN REGEXP_LIKE(page, '(.*brasilia-df.*)|(.*brasilia.*)') THEN 'brasilia-df'
            WHEN REGEXP_LIKE(page, '(.*campinas-sp.*)') THEN 'campinas-sp'
            WHEN REGEXP_LIKE(page, '.*canoas-rs.*') THEN 'canoas-rs'
            WHEN REGEXP_LIKE(page, '.*carapicuiba-sp.*') THEN 'carapicuiba-sp'
            WHEN REGEXP_LIKE(page, '.*ciudad-de-mexico-cdmx.*') THEN 'ciudad-de-mexico-cdmx'
            WHEN REGEXP_LIKE(page, '(.*contagem-mg.*)|(.*contagem-bh.*)') THEN 'contagem-mg'
            WHEN REGEXP_LIKE(page, '.*cotia-sp.*') THEN 'cotia-sp'
            WHEN REGEXP_LIKE(page, '(.*curitiba-pr.*)|(.*curitiba.*)') THEN 'curitiba-pr'
            WHEN REGEXP_LIKE(page, '.*diadema-sp.*') THEN 'diadema-sp'
            WHEN REGEXP_LIKE(page, '.*duque-de-caxias-rj.*') THEN 'duque-de-caxias-rj'
            WHEN REGEXP_LIKE(page, '.*embu-das-artes-sp.*') THEN 'embu-das-artes-sp'
            WHEN REGEXP_LIKE(page, '.*ferraz-de-vasconcelos-sp.*') THEN 'ferraz-de-vasconcelos-sp'
            WHEN REGEXP_LIKE(page, '(.*florianopolis-sc.*)|(.*florianopolis.*)') THEN 'florianopolis-sc'
            WHEN REGEXP_LIKE(page, '.*fortaleza-ce.*') THEN 'fortaleza-ce'
            WHEN REGEXP_LIKE(page, '(.*goiania-go.*)') THEN 'goiania-go'
            WHEN REGEXP_LIKE(page, '.*gravatai-rs.*') THEN 'gravatai-rs'
            WHEN REGEXP_LIKE(page, '.*guaruja-sp.*') THEN 'guaruja-sp'
            WHEN REGEXP_LIKE(page, '(.*guarulhos-sp.*)') THEN 'guarulhos-sp'
            WHEN REGEXP_LIKE(page, '.*hortolandia-sp.*') THEN 'hortolandia-sp'
            WHEN REGEXP_LIKE(page, '.*indaiatuba-sp.*') THEN 'indaiatuba-sp'
            WHEN REGEXP_LIKE(page, '.*itaquaquecetuba-sp.*') THEN 'itaquaquecetuba-sp'
            WHEN REGEXP_LIKE(page, '.*jaboatao-dos-guararapes-pe.*') THEN 'jaboatao-dos-guararapes-pe'
            WHEN REGEXP_LIKE(page, '.*jacarei-sp.*') THEN 'jacarei-sp'
            WHEN REGEXP_LIKE(page, '.*jundiai-sp.*') THEN 'jundiai-sp'
            WHEN REGEXP_LIKE(page, '.*manaus-am.*') THEN 'manaus-am'
            WHEN REGEXP_LIKE(page, '.*maua-sp.*') THEN 'maua-sp'
            WHEN REGEXP_LIKE(page, '.*mesquita-rj.*') THEN 'mesquita-rj'
            WHEN REGEXP_LIKE(page, '.*mogi-das-cruzes-sp.*') THEN 'mogi-das-cruzes-sp'
            WHEN REGEXP_LIKE(page, '.*naucalpan-de-juarez-em.*') THEN 'naucalpan-de-juarez-em'
            WHEN REGEXP_LIKE(page, '.*nilopolis-rj.*') THEN 'nilopolis-rj'
            WHEN REGEXP_LIKE(page, '.*niteroi-rj.*') THEN 'niteroi-rj'
            WHEN REGEXP_LIKE(page, '.*nova-iguacu-rj.*') THEN 'nova-iguacu-rj'
            WHEN REGEXP_LIKE(page, '.*nova-lima-mg.*') THEN 'nova-lima-mg'
            WHEN REGEXP_LIKE(page, '.*novo-hamburgo-rs.*') THEN 'novo-hamburgo-rs'
            WHEN REGEXP_LIKE(page, '.*osasco-sp.*') THEN 'osasco-sp'
            WHEN REGEXP_LIKE(page, '.*palhoca-sc.*') THEN 'palhoca-sc'
            WHEN REGEXP_LIKE(page, '.*paulinia-sp.*') THEN 'paulinia-sp'
            WHEN REGEXP_LIKE(page, '.*pinhais-pr.*') THEN 'pinhais-pr'
            WHEN REGEXP_LIKE(page, '.*porto-alegre-rs.*') THEN 'porto-alegre-rs'
            WHEN REGEXP_LIKE(page, '.*poa-sp.*') THEN 'poa-sp'
            WHEN REGEXP_LIKE(page, '.*praia-grande-sp.*') THEN 'praia-grande-sp'
            WHEN REGEXP_LIKE(page, '.*recife-pe.*') THEN 'recife-pe'
            WHEN REGEXP_LIKE(page, '.*ribeirao-das-neves-mg.*') THEN 'ribeirao-das-neves-mg'
            WHEN REGEXP_LIKE(page, '.*ribeirao-pires-sp.*') THEN 'ribeirao-pires-sp'
            WHEN REGEXP_LIKE(page, '.*ribeirao-preto-sp.*') THEN 'ribeirao-preto-sp'
            WHEN REGEXP_LIKE(page, '(.*rio-de-janeiro-rj.*)|(.*rio-de-janeiro.*)') THEN 'rio-de-janeiro-rj'
            WHEN REGEXP_LIKE(page, '.*salvador-ba.*') THEN 'salvador-ba'
            WHEN REGEXP_LIKE(page, '.*santana-de-parnaiba-sp.*') THEN 'santana-de-parnaiba-sp'
            WHEN REGEXP_LIKE(page, '.*santo-andre-sp.*') THEN 'santo-andre-sp'
            WHEN REGEXP_LIKE(page, '.*santos-sp.*') THEN 'santos-sp'
            WHEN REGEXP_LIKE(page, '.*sorocaba-sp.*') THEN 'sorocaba-sp'
            WHEN REGEXP_LIKE(page, '.*sumare-sp.*') THEN 'sumare-sp'
            WHEN REGEXP_LIKE(page, '.*suzano-sp.*') THEN 'suzano-sp'
            WHEN REGEXP_LIKE(page, '.*sao-bernardo-do-campo-sp.*') THEN 'sao-bernardo-do-campo-sp'
            WHEN REGEXP_LIKE(page, '.*sao-caetano-do-sul-sp.*') THEN 'sao-caetano-do-sul-sp'
            WHEN REGEXP_LIKE(page, '.*sao-goncalo-rj.*') THEN 'sao-goncalo-rj'
            WHEN REGEXP_LIKE(page, '.*sao-jose-dos-pinhais-pr.*') THEN 'sao-jose-dos-pinhais-pr'
            WHEN REGEXP_LIKE(page, '.*sao-jose-sc.*') THEN 'sao-jose-sc'
            WHEN REGEXP_LIKE(page, '.*sao-jose-do-rio-preto-sp.*') THEN 'sao-jose-do-rio-preto-sp'
            WHEN REGEXP_LIKE(page, '.*sao-jose-dos-campos-sp.*') THEN 'sao-jose-dos-campos-sp'
            WHEN REGEXP_LIKE(page, '.*sao-leopoldo-rs.*') THEN 'sao-leopoldo-rs'
            WHEN REGEXP_LIKE(page, '(.*sao-paulo-sp.*)|(.*sao-paulo.*)') THEN 'sao-paulo-sp'
            WHEN REGEXP_LIKE(page, '.*sao-vicente-sp.*') THEN 'sao-vicente-sp'
            WHEN REGEXP_LIKE(page, '.*taboao-da-serra-sp.*') THEN 'taboao-da-serra-sp'
            WHEN REGEXP_LIKE(page, '.*taubate-sp.*') THEN 'taubate-sp'
            WHEN REGEXP_LIKE(page, '.*uberlandia-mg.*') THEN 'uberlandia-mg'
            WHEN REGEXP_LIKE(page, '.*valinhos-sp.*') THEN 'valinhos-sp'
            WHEN REGEXP_LIKE(page, '.*viamao-rs.*') THEN 'viamao-rs'
            WHEN REGEXP_LIKE(page, '.*vila-velha-es.*') THEN 'vila-velha-es'
            WHEN REGEXP_LIKE(page, '.*vinhedo-sp.*') THEN 'vinhedo-sp'
            WHEN REGEXP_LIKE(page, '.*vitoria-es.*') THEN 'vitoria-es'
            WHEN REGEXP_LIKE(page, '.*votorantim-sp.*') THEN 'votorantim-sp'
            WHEN REGEXP_LIKE(page, '.*varzea-paulista-sp.*') THEN 'varzea-paulista-sp'
            WHEN REGEXP_LIKE(page, '.*barueri.*') THEN 'barueri-sp'
            WHEN REGEXP_LIKE(page, '.*salvador.*') THEN 'salvador-ba'
            WHEN REGEXP_LIKE(page, '(.*campinas.*)') THEN 'campinas-sp'
            WHEN REGEXP_LIKE(page, '(.*guarulhos.*)') THEN 'guarulhos-sp'
            WHEN REGEXP_LIKE(page, '.*osasco.*') THEN 'osasco-sp'
            WHEN REGEXP_LIKE(page, '.*sao-bernardo-do-campo.*') THEN 'sao-bernardo-do-campo-sp'
            WHEN REGEXP_LIKE(page, '.*sao-jose-dos-pinhais.*') THEN 'sao-jose-dos-pinhais-pr'
            WHEN REGEXP_LIKE(page, '.*porto-alegre.*') THEN 'porto-alegre-rs'
            WHEN REGEXP_LIKE(page, '.*niteroi.*') THEN 'niteroi-rj'
            WHEN REGEXP_LIKE(page, '(.*goiania.*)') THEN 'goiania-go'
            WHEN REGEXP_LIKE(page, '.*alvorada.*') THEN 'alvorada-rs'
            WHEN REGEXP_LIKE(page, '.*aparecida-de-goiania.*') THEN 'aparecida-de-goiania-go'
            WHEN REGEXP_LIKE(page, '.*belford-roxo.*') THEN 'belford-roxo-rj'
            WHEN REGEXP_LIKE(page, '.*belem.*') THEN 'belem-pa'
            WHEN REGEXP_LIKE(page, '.*betim.*') THEN 'betim-mg'
            WHEN REGEXP_LIKE(page, '.*canoas.*') THEN 'canoas-rs'
            WHEN REGEXP_LIKE(page, '.*carapicuiba.*') THEN 'carapicuiba-sp'
            WHEN REGEXP_LIKE(page, '.*ciudad-de-mexico.*') THEN 'ciudad-de-mexico-cdmx'
            WHEN REGEXP_LIKE(page, '(.*contagem.*)') THEN 'contagem-mg'
            WHEN REGEXP_LIKE(page, '.*cotia.*') THEN 'cotia-sp'
            WHEN REGEXP_LIKE(page, '.*diadema.*') THEN 'diadema-sp'
            WHEN REGEXP_LIKE(page, '.*duque-de-caxias.*') THEN 'duque-de-caxias-rj'
            WHEN REGEXP_LIKE(page, '.*embu-das-artes.*') THEN 'embu-das-artes-sp'
            WHEN REGEXP_LIKE(page, '.*ferraz-de-vasconcelos.*') THEN 'ferraz-de-vasconcelos-sp'
            WHEN REGEXP_LIKE(page, '.*fortaleza.*') THEN 'fortaleza-ce'
            WHEN REGEXP_LIKE(page, '.*gravatai.*') THEN 'gravatai-rs'
            WHEN REGEXP_LIKE(page, '.*guaruja.*') THEN 'guaruja-sp'
            WHEN REGEXP_LIKE(page, '.*hortolandia.*') THEN 'hortolandia-sp'
            WHEN REGEXP_LIKE(page, '.*indaiatuba.*') THEN 'indaiatuba-sp'
            WHEN REGEXP_LIKE(page, '.*itaquaquecetuba.*') THEN 'itaquaquecetuba-sp'
            WHEN REGEXP_LIKE(page, '.*jaboatao-dos-guararapes.*') THEN 'jaboatao-dos-guararapes-pe'
            WHEN REGEXP_LIKE(page, '.*jacarei.*') THEN 'jacarei-sp'
            WHEN REGEXP_LIKE(page, '.*jundiai.*') THEN 'jundiai-sp'
            WHEN REGEXP_LIKE(page, '.*manaus.*') THEN 'manaus-am'
            WHEN REGEXP_LIKE(page, '.*maua.*') THEN 'maua-sp'
            WHEN REGEXP_LIKE(page, '.*mesquita.*') THEN 'mesquita-rj'
            WHEN REGEXP_LIKE(page, '.*mogi-das-cruzes.*') THEN 'mogi-das-cruzes-sp'
            WHEN REGEXP_LIKE(page, '.*naucalpan-de-juarez.*') THEN 'naucalpan-de-juarez-em'
            WHEN REGEXP_LIKE(page, '.*nilopolis.*') THEN 'nilopolis-rj'
            WHEN REGEXP_LIKE(page, '.*nova-iguacu.*') THEN 'nova-iguacu-rj'
            WHEN REGEXP_LIKE(page, '.*nova-lima.*') THEN 'nova-lima-mg'
            WHEN REGEXP_LIKE(page, '.*novo-hamburgo.*') THEN 'novo-hamburgo-rs'
            WHEN REGEXP_LIKE(page, '.*palhoca.*') THEN 'palhoca-sc'
            WHEN REGEXP_LIKE(page, '.*paulinia.*') THEN 'paulinia-sp'
            WHEN REGEXP_LIKE(page, '.*pinhais.*') THEN 'pinhais-pr'
            WHEN REGEXP_LIKE(page, '.*praia-grande.*') THEN 'praia-grande-sp'
            WHEN REGEXP_LIKE(page, '.*recife.*') THEN 'recife-pe'
            WHEN REGEXP_LIKE(page, '.*ribeirao-das-neves.*') THEN 'ribeirao-das-neves-mg'
            WHEN REGEXP_LIKE(page, '.*ribeirao-pires.*') THEN 'ribeirao-pires-sp'
            WHEN REGEXP_LIKE(page, '.*ribeirao-preto.*') THEN 'ribeirao-preto-sp'
            WHEN REGEXP_LIKE(page, '.*santana-de-parnaiba.*') THEN 'santana-de-parnaiba-sp'
            WHEN REGEXP_LIKE(page, '.*santo-andre.*') THEN 'santo-andre-sp'
            WHEN REGEXP_LIKE(page, '.*santos.*') THEN 'santos-sp'
            WHEN REGEXP_LIKE(page, '.*sorocaba.*') THEN 'sorocaba-sp'
            WHEN REGEXP_LIKE(page, '.*sumare.*') THEN 'sumare-sp'
            WHEN REGEXP_LIKE(page, '.*suzano.*') THEN 'suzano-sp'
            WHEN REGEXP_LIKE(page, '.*sao-caetano-do-sul.*') THEN 'sao-caetano-do-sul-sp'
            WHEN REGEXP_LIKE(page, '.*sao-goncalo.*') THEN 'sao-goncalo-rj'
            WHEN REGEXP_LIKE(page, '.*sao-jose-dos-pinhais.*') THEN 'sao-jose-dos-pinhais-pr'
            WHEN REGEXP_LIKE(page, '.*sao-jose.*') THEN 'sao-jose-sc'
            WHEN REGEXP_LIKE(page, '.*sao-jose-do-rio-preto.*') THEN 'sao-jose-do-rio-preto-sp'
            WHEN REGEXP_LIKE(page, '.*sao-jose-dos-campos.*') THEN 'sao-jose-dos-campos-sp'
            WHEN REGEXP_LIKE(page, '.*sao-leopoldo.*') THEN 'sao-leopoldo-rs'
            WHEN REGEXP_LIKE(page, '.*sao-vicente.*') THEN 'sao-vicente-sp'
            WHEN REGEXP_LIKE(page, '.*taboao-da-serra.*') THEN 'taboao-da-serra-sp'
            WHEN REGEXP_LIKE(page, '.*taubate.*') THEN 'taubate-sp'
            WHEN REGEXP_LIKE(page, '.*uberlandia.*') THEN 'uberlandia-mg'
            WHEN REGEXP_LIKE(page, '.*valinhos.*') THEN 'valinhos-sp'
            WHEN REGEXP_LIKE(page, '.*viamao.*') THEN 'viamao-rs'
            WHEN REGEXP_LIKE(page, '.*vila-velha.*') THEN 'vila-velha-es'
            WHEN REGEXP_LIKE(page, '.*vinhedo.*') THEN 'vinhedo-sp'
            WHEN REGEXP_LIKE(page, '.*vitoria.*') THEN 'vitoria-es'
            WHEN REGEXP_LIKE(page, '.*votorantim.*') THEN 'votorantim-sp'
            WHEN REGEXP_LIKE(page, '.*varzea-paulista.*') THEN 'varzea-paulista-sp'
            WHEN REGEXP_LIKE(page, '.*americana.*') THEN 'americana-sp'
            WHEN REGEXP_LIKE(page, '.*poa.*') THEN 'poa-sp'
            ELSE 'Other'
        END AS cidades,
        CASE 
            WHEN page LIKE '%proprietario.quintoandar%' THEN 'Proprietários'
            WHEN page LIKE '%meulugar.quintoandar%' THEN 'MeuLugar'
            WHEN page LIKE '%conteudos.quintoandar%' THEN 'Conteúdos'
            WHEN page LIKE '%help.quintoandar%' THEN 'Help'
            WHEN page LIKE '%br/alugar/%' THEN 'Busca aluguel'
            WHEN page LIKE '%br/comprar/%' THEN 'Busca compra'
            WHEN page LIKE '%br/imovel/%' OR page LIKE '%br/apartamento/%' THEN 'Listing'
            WHEN page LIKE '%br/regioes-atendidas/%' OR page LIKE '%br/morar/%' THEN 'Regiões atendidas'
            WHEN page LIKE '%/guias/%' THEN 'MeuLugar'
            WHEN page LIKE '%br/condominio/%' THEN 'Condomínio'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br' THEN 'Home'
            ELSE 'Other'
        END AS cluster_de_paginas,
        CASE
            WHEN REGEXP_LIKE(page, '(rs-brasil)') THEN 'RS'
            WHEN REGEXP_LIKE(page, '(sp-brasil)') THEN 'SP'
            WHEN REGEXP_LIKE(page, '(rj-brasil)') THEN 'RJ'
            WHEN REGEXP_LIKE(page, '(mg-brasil)') THEN 'MG'
            WHEN REGEXP_LIKE(page, '(bh-brasil)') THEN 'MG'
            WHEN REGEXP_LIKE(page, '(pa-brasil)') THEN 'PA'
            WHEN REGEXP_LIKE(page, '(df-brasil)') THEN 'DF'
            WHEN REGEXP_LIKE(page, '(cdmx-brasil)') THEN 'MX'
            WHEN REGEXP_LIKE(page, '(pr-brasil)') THEN 'PR'
            WHEN REGEXP_LIKE(page, '(sc-brasil)') THEN 'SC'
            WHEN REGEXP_LIKE(page, '(ce-brasil)') THEN 'CE'
            WHEN REGEXP_LIKE(page, '(pe-brasil)') THEN 'PE'
            WHEN REGEXP_LIKE(page, '(am-brasil)') THEN 'AM'
            WHEN REGEXP_LIKE(page, '(em-brasil)') THEN 'MX'
            WHEN REGEXP_LIKE(page, '(es-brasil)') THEN 'ES'
            WHEN REGEXP_LIKE(page, '(ba-brasil)') THEN 'BA'
            WHEN REGEXP_LIKE(page, '(go-brasil)') THEN 'GO'
            WHEN REGEXP_LIKE(page, '(-rs)') THEN 'RS'
            WHEN REGEXP_LIKE(page, '(-sp)') THEN 'SP'
            WHEN REGEXP_LIKE(page, '(-rj)') THEN 'RJ'
            WHEN REGEXP_LIKE(page, '(-mg)') THEN 'MG'
            WHEN REGEXP_LIKE(page, '(-bh)') THEN 'MG'
            WHEN (REGEXP_LIKE(page, '(-pa$)') OR REGEXP_LIKE(page, '(-pa\/.*)')) THEN 'PA'
            WHEN REGEXP_LIKE(page, '(-df)') THEN 'DF'
            WHEN REGEXP_LIKE(page, '(-cdmx)') THEN 'MX'
            WHEN (REGEXP_LIKE(page, '(-pr$)') OR REGEXP_LIKE(page, '(-pr\/.*)')) THEN 'PR'
            WHEN REGEXP_LIKE(page, '(-sc)') THEN 'SC'
            WHEN (REGEXP_LIKE(page, '(-ce$)') OR REGEXP_LIKE(page, '(-ce\/.*)')) THEN 'CE'
            WHEN (REGEXP_LIKE(page, '(-pe$)') OR REGEXP_LIKE(page, '(-pe\/.*)')) THEN 'PE'
            WHEN (REGEXP_LIKE(page, '(-am$)') OR REGEXP_LIKE(page, '(-am\/.*)')) THEN 'AM'
            WHEN (REGEXP_LIKE(page, '(-em$)') OR REGEXP_LIKE(page, '(-em\/.*)')) THEN 'MX'
            WHEN (REGEXP_LIKE(page, '(-es$)') OR REGEXP_LIKE(page, '(-es\/.*)')) THEN 'ES'
            WHEN (REGEXP_LIKE(page, '(-ba$)') OR REGEXP_LIKE(page, '(-ba\/.*)')) THEN 'BA'
            WHEN (REGEXP_LIKE(page, '(-go$)') OR REGEXP_LIKE(page, '(-go\/.*)')) THEN 'GO'
            ELSE 'Other'
        END AS estado,
        CASE 
            WHEN page like '%proprietario.quintoandar%' THEN 'Supply'
            WHEN page like '%meulugar.quintoandar%' OR page like '%conteudos.quintoandar%' THEN 'Content'
            WHEN page like '%help.quintoandar%' THEN 'Help'
            WHEN page LIKE '%br/alugar/%' OR page LIKE '%br/comprar/%' OR page LIKE '%br/imovel/%' OR page LIKE '%br/apartamento/%' THEN 'Transacional'
            WHEN page LIKE '%br/regioes-atendidas%' OR page LIKE '%br/condominio/%' OR page LIKE '%br/morar/%' OR page LIKE '%/guias/%' THEN 'Informacional'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br' THEN 'Home'
            ELSE 'Other'
        END AS estruturas,
        CASE
            WHEN page LIKE '%meulugar.quintoandar%' OR page LIKE '%conteudos.quintoandar%' THEN 'n/a'
            WHEN page LIKE '%proprietario.quintoandar%' OR page LIKE '%help.quintoandar%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br/auth%' OR page LIKE 'https://www.quintoandar.com.br/tenants%' THEN 'n/a'
            WHEN page LIKE '%.br/imovel/%' OR page LIKE '%.br/apartamento/%' THEN 'Imóveis'
            WHEN page LIKE '%br/condominio/%' AND page REGEXP '/r.-|/r-|/rua-|/alameda-|/av.-|/av-|/avenida-|/tv.-|/tv-|/travessa-|/servidao-|/rod.-|/estrada-|/estr.-' THEN 'Endereço Condomínio'
            WHEN page LIKE '%br/condominio/%' THEN 'Nome Condomínio'
            WHEN page LIKE '%br/morar/%' THEN 'Cidades'
            WHEN page REGEXP '/r.-|/r-|/rua-|/alameda-|/av.-|/av-|/avenida-|/tv.-|/tv-|/travessa-|/servidao-|/rod.-|/estrada-|/estr.-' THEN 'Ruas'
            WHEN page LIKE '%/zona-%' THEN 'Zonas'
            WHEN page REGEXP '/alvorada-rs-brasil|/americana-sp-brasil|/aparecida-de-goiania-go-brasil|/barueri-sp-brasil|/belford-roxo-rj-brasil|/belo-horizonte-mg-brasil|/belo-horizonte-bh-brasil|/belem-pa-brasil|/betim-mg-brasil|/brasilia-df-brasil|/campinas-sp-brasil|/canoas-rs-brasil|/carapicuiba-sp-brasil|/ciudad-de-mexico-cdmx-brasil|/contagem-mg-brasil|/contagem-bh-brasil|/cotia-sp-brasil|/curitiba-pr-brasil|/diadema-sp-brasil|/duque-de-caxias-rj-brasil|/embu-das-artes-sp-brasil|/ferraz-de-vasconcelos-sp-brasil|/florianopolis-sc-brasil|/fortaleza-ce-brasil|/goiania-go-brasil|/gravatai-rs-brasil|/guaruja-sp-brasil|/guarulhos-sp-brasil|/hortolandia-sp-brasil|/indaiatuba-sp-brasil|/itaquaquecetuba-sp-brasil|/jaboatao-dos-guararapes-pe-brasil|/jacarei-sp-brasil|/jundiai-sp-brasil|/manaus-am-brasil|/maua-sp-brasil|/mesquita-rj-brasil|/mogi-das-cruzes-sp-brasil|/naucalpan-de-juarez-em-brasil|/nilopolis-rj-brasil|/niteroi-rj-brasil|/nova-iguacu-rj-brasil|/nova-lima-mg-brasil|/novo-hamburgo-rs-brasil|/osasco-sp-brasil|/palhoca-sc-brasil|/paulinia-sp-brasil|/pinhais-pr-brasil|/porto-alegre-rs-brasil|/poa-sp-brasil|/praia-grande-sp-brasil|/recife-pe-brasil|/ribeirao-das-neves-mg-brasil|/ribeirao-pires-sp-brasil|/ribeirao-preto-sp-brasil|/rio-de-janeiro-rj-brasil|/salvador-ba-brasil|/santana-de-parnaiba-sp-brasil|/santo-andre-sp-brasil|/santos-sp-brasil|/sorocaba-sp-brasil|/sumare-sp-brasil|/suzano-sp-brasil|/sao-bernardo-do-campo-sp-brasil|/sao-caetano-do-sul-sp-brasil|/sao-goncalo-rj-brasil|/sao-jose-dos-pinhais-pr-brasil|/sao-jose-sc-brasil|/sao-jose-do-rio-preto-sp-brasil|/sao-jose-dos-campos-sp-brasil|/sao-leopoldo-rs-brasil|/sao-paulo-sp-brasil|/sao-vicente-sp-brasil|/taboao-da-serra-sp-brasil|/taubate-sp-brasil|/uberlandia-mg-brasil|/valinhos-sp-brasil|/viamao-rs-brasil|/vila-velha-es-brasil|/vinhedo-sp-brasil|/vitoria-es-brasil|/votorantim-sp-brasil|/varzea-paulista-sp-brasil' THEN 'Cidades'
            WHEN page REGEXP 'shopping-|/metro-|escola-|cinema-|/mercado-|universidade-|academia-|hospital-|instituto-|/sh-|/estacao-|/espaco-|faculdade-|farmacia-|/galeria-|fundacao-|museu-|loja-|/terminal-|shopping-|teatro-|universitaria|/unidade-de-|ufrj|uff|uerj|unb|unicamp|uerj|/uci-|drogaria-|ufabc-|ufmg-|supermercado|cozinha-|colegio-|creche-|conjunto-|lanches-|habitacoes-|sesc-|senac-|restaurante-|/praca-|condominio-|/conj.-hab.-|/conj.-res.-|/conj.-res.-|confeitaria-|cinema-|churrascaria|sushi|pizza|/centro-medico-|centro-universitario|centro-de-saude|centro-de-tradicoes|centro-medico|centro-comercial|/arena-|crossfit|ambulatorio|aeroporto-|instituto-' THEN 'POI'
            WHEN page LIKE '%.com.br/s/%' AND page REGEXP '-sao-paulo-sp|-fortaleza-ce|-rio-de-janeiro-rj|-campinas-sp|-porto-alegre-rs|-santo-andre-sp|-belo-horizonte-mg|-novo-hamburgo-rs|-salvador-ba|-osasco-sp|-niteroi-rj|-curitiba-pr|-santos-sp|-sao-jose-dos-pinhais-pr|-florianopolis-sc|-sao-caetano-do-sul-sp' THEN 'Cidades'
            WHEN page LIKE '%-brasil' OR page LIKE '%-brasil/%' OR page LIKE '%-brasil-%' OR page LIKE '%-brasil?%' THEN 'Bairros'
            ELSE 'POI'
        END AS nivel_localizacao,
        CASE
            WHEN REGEXP_LIKE(page, '(/r.-)|(/r-)') THEN '/r'
            WHEN REGEXP_LIKE(page, '(/av.-)|(/av-)') THEN '/av'
            WHEN REGEXP_LIKE(page, '(/tv.-)|(/tv-)') THEN '/tv'
            WHEN REGEXP_LIKE(page, '(/rod.-)') THEN '/rod'
            WHEN REGEXP_LIKE(page, '(/estr.-)') THEN '/estr'
            WHEN REGEXP_LIKE(page, '(/rua-)') THEN '/rua'
            WHEN REGEXP_LIKE(page, '(/alameda-)') THEN '/alameda'
            WHEN REGEXP_LIKE(page, '(/avenida-)') THEN '/avenida'
            WHEN REGEXP_LIKE(page, '(/travessa-)') THEN '/travessa'
            WHEN REGEXP_LIKE(page, '(/servidao-)') THEN '/servidao'
            WHEN REGEXP_LIKE(page, '(/estrada-)') THEN '/estrada'
            WHEN REGEXP_LIKE(page, '(/sqn-)|(/sqs)|(/st.-)|(/qr-)|(/qn-)|(/qr-)|(/qs-)') THEN 'streets of Brasília'
            ELSE 'n/a'
        END AS street_abbreviations,
        CASE
            WHEN REGEXP_LIKE(page, '/s/') THEN 'Verbolia'
            WHEN REGEXP_LIKE(page, '(/unb-)|(universidade-)|(/ufrj-)|(/ufmg-)|(/usp-)|(/ubs-)|(/unicamp-)|(universitario-)|(/puc-)|(/uerj-)|(/ufabc-)|(espm-)|(cefet-)|(uff-)|(faculdade)|(fundacao-getulio-vargas-)|(/ufrgs-)|(escola-)|(colegio-)|(sesc)|(sesi)|(fmusp-)|(universitaria-)|(senai)|(educacao)|(educacional)|(usp)|(estacio)|(cursos)|(creche)|(ensino)|(ceep)|(ciaa)|(uninove)|(anhembi)|(elite-)|(unifesp)|(professor)|(senac)|(fgv)|(unirio)|(profissional)|(formacao)|(ibmec)|(fametro)|(esefid)') THEN 'Instituições de ensino'
            WHEN REGEXP_LIKE(page, '(shopping)|(vogue-square)|(centro-comercial)|(comercial-)|(patio-higienopolis)|(expo-center-)|(loja)|(patio-batel)|(club)|(horto)|(mall)|(poupatempo)|(pague-menos)|(magazine-luiza)|(inss)|(forum)|(caixa-economica)|(atacado)|(center-)|(centro-de-convencoes)|(outlet)|(distribuidora)|(brecho)|(loteria)|(trenzinho)|(consultoria)|(cnen)|(caixa-)|(garimpei)|(banco-)|(atelier)|(secretaria)|(shell)|(cartorio)|(itau-)|(bradesco)|(noivas)|(garage-vintage)') THEN 'Shoppings e Centros comerciais'
            WHEN REGEXP_LIKE(page, 'aeroporto') THEN 'Aeroporto'
            WHEN REGEXP_LIKE(page, '(mercado)|(walmart)|(wallmart)|/(pao-de-acucar)|(carrefour)|(market-)|(prezunic)|(br-mania)') THEN 'Mercado'
            WHEN REGEXP_LIKE(page, 'igreja') THEN 'Igreja'
            WHEN REGEXP_LIKE(page, '(hospital)|(centro-de-saude)|(posto-de-saude)|(upa-24h)|(clinica-da-familia)|(clinica-)|(-de-saude)|(drogaria)|(drogamario)|(drogaria)|(droga-raia)|(unimed)|(oftalmologista)|(farmacia)|(farmaextra)|(drogamil)|(medica)|(sergio-franco)|(pontro-atendimento)|(farmaextra)|(-de-atendimento)|(upa)|(droga-baby)|(medico)|(droga-coop)|(fisioterapia)|(terapia)|(medicina)|(laboratorio)') THEN 'Área da saúde'
            WHEN REGEXP_LIKE(page, '(/estacao-)|(/terminal-)') THEN 'Estações de transporte público'
            WHEN REGEXP_LIKE(page, '(/parque-)|(/praia)|(/praca-)|(bosque-)') THEN 'Áreas verdes'
            WHEN REGEXP_LIKE(page, '(policia-)|(-dp-)|(delegacia)') THEN 'Polícia'
            WHEN REGEXP_LIKE(page, '(museu-)|(teatro-)|(planetario-)|(zoo-)|(zoologico-)|(-artes-)|(-arte-)|(feira)|(allianz-parque)|(cinema)|(galeria)|(discotek)|(fundacao)|(espaco-)|(instituto)|(feirinha)|(estadio)|(kinoplex)|(uci-new-york-city)|(cultura)|(cinepolis)|(arena)|(festas)|(cine-topazio)|(opera)|(musica)') THEN 'Espaços Culturais'
            WHEN REGEXP_LIKE(page, '(subway-)|(oakberry-)|(restaurante-)|(comida-)|(japones-)|(sushi-)|(pizza)|(tapioquinha)|(bar-)|(cafe-)|(cafeteira)|(chopp)|(lanche)|(churrascaria)|(acai-prime)|(pub)|(ristorante)|(madero)|(buffet)|(ostras)|(boteco)|(artesano)|(pastel)|(venga)|(adega)|(botequim)|(espetaria)|(kfc)|(gourmet)|(outback)|(carnes)|(japa)|(food)|(cervejaria)|(burguer)|(salad)|(beer)|(mercearia)|(void)|(bobs)|(yakisoba)|(kiosque)|(koni)|(bistro)|(churros)|(acai-)|(burger)|(sucos)|(balada-mix)|(sanduiche)|(cozinha)|(padaria)|(hamburgu)|(kopenhagen)') THEN 'Estabelecimentos de comida'
            WHEN REGEXP_LIKE(page, '(conj.-hab.-)|(conj-hab-)|(conjunto-habitacional-)|(conj.-res.-)|(conj-res-)|(conjunto-residencial-)|(condominio)|(habitacoes)|(conjunto-)') THEN 'Conjunto Residencial'
            WHEN REGEXP_LIKE(page, '(complexo-esportivo-)|(esporte)|(futebol)|(esportivo)|(coreo-danca-)|(academia)|(smart-fit)|(olimpico)|(yoga)|(fit-)|(ballet)|(velocity)|(sports)') THEN 'Complexos Esportivos'
            ELSE 'Other'
        END AS tipo_poi
    FROM
        datalake_google_search_console_clean.report_by_page_and_query
    WHERE
        DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND country = 'bra'
),
layer2 AS (
    SELECT
        site_url,
        device,
        page,
        is_branded,
        query,
        country,
        dt_created,
        year,
        month,
        day,
        domain,
        slug,
        subtitle_content,
        regiao_busca,
        caminho_da_pagina,
        cidades,
        cluster_de_paginas,
        estado,
        estruturas,
        nivel_localizacao,
        street_abbreviations,
        tipo_poi,
        ctr,
        clicks,
        position,
        impressions,
        posimp,
        CASE
            WHEN page LIKE '%meulugar.quintoandar%' OR page LIKE '%conteudos.quintoandar%' OR page LIKE '%/guias/%' THEN 'n/a'
            WHEN page LIKE '%proprietario.quintoandar%' OR page LIKE '%help.quintoandar%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br/auth%' OR page LIKE 'https://www.quintoandar.com.br/tenants%' THEN 'n/a'
            WHEN page LIKE '%/regioes-atendidas%' OR page LIKE '%br/condominio%' OR page LIKE '%br/morar%' THEN 'n/a' 
            WHEN page LIKE '%.br/imovel/%' OR page LIKE '%.br/apartamento%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br' THEN 'n/a'
            WHEN page REGEXP '/s/' THEN 'Páginas com /s/'
            WHEN 
                page REGEXP '/apartamento|/apartamento-cobertura|/casacondominio|/casa|/kitnet' 
                AND page REGEXP '/academia|/elevador|/piscina|/portaria-24h|/proximo-ao-metro' 
                AND page REGEXP '-quartos|-banheiros|-vagas|-venda|-aluguel|-m2|/ar-condicionado|/varanda|/varanda-gourmet|/mobiliado|/armarios-na-cozinha|/armarios-no-quarto|/aceita-pets' 
                AND page NOT LIKE '%/academia-%' 
            THEN 'Tipo + Característica do Imóvel + Condomínio'
            WHEN 
                page REGEXP '/apartamento|/apartamento-cobertura|/casacondominio|/casa|/kitnet' 
                AND page REGEXP '-quartos|-banheiros|-vagas|-venda|-aluguel|-m2|/ar-condicionado|/varanda|/varanda-gourmet|/mobiliado|/armarios-na-cozinha|/armarios-no-quarto|/aceita-pets' 
            THEN 'Tipo + Característica do Imóvel'
            WHEN 
                page REGEXP '/apartamento|/apartamento-cobertura|/casacondominio|/casa|/kitnet' 
                AND page REGEXP '/academia|/elevador|/piscina|/portaria-24h|/proximo-ao-metro' 
                AND page NOT LIKE '%/academia-%' 
            THEN 'Tipo do Imóvel + Condomínio'
            WHEN 
                page REGEXP '/academia|/elevador|/piscina|/portaria-24h|/proximo-ao-metro' 
                AND page REGEXP '-quartos|-banheiros|-vagas|-venda|-aluguel|-m2|/ar-condicionado|/varanda|/varanda-gourmet|/mobiliado|/armarios-na-cozinha|/armarios-no-quarto|/aceita-pets' 
                AND page NOT LIKE '%/academia-%' 
            THEN 'Característica do Imóvel + Condomínio'
            WHEN page REGEXP '/apartamento|/apartamento-cobertura|/casacondominio|/casa|/kitnet' THEN 'Tipo do Imóvel' 
            WHEN page REGEXP '-quartos|-banheiros|-vagas|-venda|-aluguel|-m2|/ar-condicionado|/varanda|/varanda-gourmet|/mobiliado|/armarios-na-cozinha|/armarios-no-quarto|/aceita-pets' THEN 'Característica do Imóvel' 
            WHEN page REGEXP '/academia|/elevador|/piscina|/portaria-24h|/proximo-ao-metro' AND page NOT LIKE '%/academia-%' THEN 'Condomínio'
            WHEN page REGEXP '/originals' THEN 'Originals'
            ELSE 'Other'
        END AS combinacao_de_filtros,
        CASE
            WHEN page LIKE '%meulugar.quintoandar%' OR page LIKE '%conteudos.quintoandar%' OR page LIKE '%/guias/%' THEN 'n/a'
            WHEN page LIKE '%proprietario.quintoandar%' OR page LIKE '%help.quintoandar%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br/auth%' OR page LIKE 'https://www.quintoandar.com.br/tenants%' THEN 'n/a'
            WHEN REGEXP_LIKE(caminho_da_pagina, '/imovel/[0-9]/') THEN 'n/a'
            WHEN estruturas = 'Informacional' THEN 'n/a'
            WHEN estruturas = 'Listing' THEN 'n/a'
            WHEN REGEXP_LIKE(caminho_da_pagina, '/s/') THEN 'with filter'
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)') THEN 'with filter'
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)') THEN 'with filter'
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)/(.*)/(.*)') THEN 'with filter'
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)/(.*)') THEN 'with filter'
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)') THEN 'without filter'
            ELSE 'n/a'
        END AS filtro,
        CASE
            WHEN page LIKE '%meulugar.quintoandar%' OR page LIKE '%conteudos.quintoandar%' OR page LIKE '%/guias/%' THEN 'n/a'
            WHEN page LIKE '%proprietario.quintoandar%' OR page LIKE '%help.quintoandar%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br/auth%' OR page LIKE 'https://www.quintoandar.com.br/tenants%' THEN 'n/a'
            WHEN estruturas = 'Informacional' THEN 'n/a'
            WHEN cluster_de_paginas = 'Listing' THEN 'n/a'
            WHEN REGEXP_LIKE(page,'/proximo-ao-metro') THEN '/proximo-ao-metro'
            WHEN (REGEXP_LIKE(page,'/academia') AND page != '.*/academia-.*') THEN '/academia'
            WHEN REGEXP_LIKE(page,'/elevador') THEN '/elevador'
            WHEN REGEXP_LIKE(page,'/piscina') THEN '/piscina'
            WHEN REGEXP_LIKE(page,'/portaria-24h') THEN '/portaria-24h'
        ELSE 'n/a'
        END AS filtro_condo,
        CASE
            WHEN page LIKE '%meulugar.quintoandar%' OR page LIKE '%conteudos.quintoandar%' OR page LIKE '%/guias/%' THEN 'n/a'
            WHEN page LIKE '%proprietario.quintoandar%' OR page LIKE '%help.quintoandar%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br/auth%' OR page LIKE 'https://www.quintoandar.com.br/tenants%' THEN 'n/a'
            WHEN estruturas = 'Informacional' THEN 'n/a'
            WHEN cluster_de_paginas = 'Listing' THEN 'n/a'
            WHEN REGEXP_LIKE(page,'/.*-quartos') THEN '/.*-quartos'
            WHEN REGEXP_LIKE(page,'/.*-banheiros') THEN '/.*-banheiros'
            WHEN REGEXP_LIKE(page,'/.*-vagas') THEN '/.*-vagas'
            WHEN REGEXP_LIKE(page,'/de-.*-a-.*-venda') THEN '/de-.*-a-.*-venda'
            WHEN REGEXP_LIKE(page,'/de-.*-a-.*-aluguel') THEN '/de-.*-a-.*-aluguel'
            WHEN REGEXP_LIKE(page,'/de-.*-a-.*-m2') THEN '/de-.*-a-.*-m2'
            WHEN REGEXP_LIKE(page,'/mobiliado') THEN '/mobiliado'
            WHEN REGEXP_LIKE(page,'/armarios-na-cozinha') THEN '/armarios-na-cozinha'
            WHEN REGEXP_LIKE(page,'/armarios-no-quarto') THEN '/armarios-no-quarto'
            WHEN REGEXP_LIKE(page,'/aceita-pets') THEN '/aceita-pets'
            WHEN REGEXP_LIKE(page,'/originals') THEN '/originals'
            WHEN REGEXP_LIKE(page,'/apartamento-cobertura') THEN '/apartamento-cobertura'
            WHEN REGEXP_LIKE(page,'/varanda-gourmet') THEN '/varanda-gourmet'
            WHEN REGEXP_LIKE(page,'/varanda') THEN '/varanda'
            WHEN REGEXP_LIKE(page,'/ar-condicionado') THEN '/ar-condicionado'
            ELSE 'n/a'
        END AS filtro_house_char,
        CASE
            WHEN page LIKE '%meulugar.quintoandar%' OR page LIKE '%conteudos.quintoandar%' OR page LIKE '%/guias/%' THEN 'n/a'
            WHEN page LIKE '%proprietario.quintoandar%' OR page LIKE '%help.quintoandar%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br/auth%' OR page LIKE 'https://www.quintoandar.com.br/tenants%' THEN 'n/a'
            WHEN estruturas = 'Informacional' THEN 'n/a'
            WHEN cluster_de_paginas = 'Listing' THEN 'n/a'
            WHEN REGEXP_LIKE(page,'/apartamento') THEN '/apartamento'
            WHEN REGEXP_LIKE(page,'/casacondominio') THEN '/casacondominio'
            WHEN REGEXP_LIKE(page,'/casa') THEN '/casa'
            WHEN REGEXP_LIKE(page,'/kitnet') THEN '/kitnet'
            WHEN REGEXP_LIKE(page,'/s/') THEN '/s/'
            ELSE 'n/a'
        END AS filtro_house_type,
        CASE
            WHEN page LIKE '%meulugar.quintoandar%' OR page LIKE '%conteudos.quintoandar%' OR page LIKE '%/guias/%' THEN 'n/a'
            WHEN page LIKE '%proprietario.quintoandar%' OR page LIKE '%help.quintoandar%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br/auth%' OR page LIKE 'https://www.quintoandar.com.br/tenants%' THEN 'n/a'
            WHEN page LIKE '%/regioes-atendidas%' OR page LIKE '%br/condominio%' OR page LIKE '%br/morar%' THEN 'n/a' 
            WHEN page LIKE '%.br/imovel/%' OR page LIKE '%.br/apartamento%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br' THEN 'n/a'
            WHEN CONTAINS(page,'/apartamento') THEN 'Apartamento'
            WHEN CONTAINS(page,'/casacondominio') THEN 'Casa Condomínio'
            WHEN CONTAINS(page,'/casa') THEN 'Casa'
            WHEN CONTAINS(page,'/kitnet') THEN 'Kitnet'
            WHEN CONTAINS(page,'-quartos') THEN 'Quartos'
            WHEN CONTAINS(page,'-banheiros') THEN 'Banheiros' 
            WHEN CONTAINS(page,'-vagas') THEN 'Vagas'
            WHEN page REGEXP '-venda|-aluguel' THEN 'Valor'
            WHEN CONTAINS(page,'-m2') THEN 'Área'
            WHEN page REGEXP '/mobiliado|/armarios-na-cozinha|/armarios-no-quarto' THEN 'Mobílias'
            WHEN CONTAINS(page,'/aceita-pets') THEN 'Pets'
            WHEN CONTAINS(page,'/proximo-ao-metro') THEN 'Metro'
            WHEN CONTAINS(page,'/originals') THEN 'QuintoAndar Originals'
            WHEN page REGEXP '/academia|/elevador|/piscina|/portaria-24h' AND page NOT LIKE '%/academia-%' THEN 'Condomínio'
            WHEN page REGEXP '/ar-condicionado|/varanda|/varanda-gourmet' THEN 'Comodidades'
            WHEN CONTAINS(page,'/s/') AND page REGEXP '-apartamento|-apto' THEN 'Apartamento'
            WHEN CONTAINS(page,'/s/') AND CONTAINS(page,'-casa') THEN 'Casa'
            WHEN CONTAINS(page,'/s/') AND CONTAINS(page,'-kitnet-ou-studio') THEN 'Kitnet'
            ELSE 'Other'   
        END AS filtro_1,
        CASE
            WHEN page LIKE '%meulugar.quintoandar%' OR page LIKE '%conteudos.quintoandar%' OR page LIKE '%/guias/%' THEN 'n/a'
            WHEN page LIKE '%proprietario.quintoandar%' OR page LIKE '%help.quintoandar%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br/auth%' OR page LIKE 'https://www.quintoandar.com.br/tenants%' THEN page
            WHEN REGEXP_LIKE(page, 'com.br/imovel/') THEN page
            WHEN estruturas = 'Informacional' THEN page
            WHEN cluster_de_paginas = 'Listing' THEN page
            WHEN page = 'https://www.quintoandar.com.br/' THEN page
            WHEN REGEXP_LIKE(caminho_da_pagina, '/s/') THEN page
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)') THEN REGEXP_EXTRACT(page, '(^https://[^/]+/[^/]+/[^/]+/[^/]+)/[^/]+/[^/]+/[^/]+/[^/]+/')
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)') THEN REGEXP_EXTRACT(page, '(^https://[^/]+/[^/]+/[^/]+/[^/]+)/[^/]+/[^/]+/[^/]+/')
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)/(.*)/(.*)/(.*)') THEN  REGEXP_EXTRACT(page, '(^https://[^/]+/[^/]+/[^/]+/[^/]+)/[^/]+/[^/]+/')
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)/(.*)/(.*)') THEN REGEXP_EXTRACT(page, '(^https://[^/]+/[^/]+/[^/]+/[^/]+)/[^/]+/')
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)/(.*)') THEN REGEXP_EXTRACT(page, '(^https://[^/]+/[^/]+/[^/]+/[^/]+)/')
            WHEN REGEXP_LIKE(caminho_da_pagina, '/(.*)/(.*)/(.*)') THEN REGEXP_EXTRACT(page, '(^https://[^/]+/[^/]+/[^/]+/[^/]+)')
            ELSE page
        END AS lp_sem_filtro,
        CASE
            WHEN page LIKE '%meulugar.quintoandar%' OR page LIKE '%conteudos.quintoandar%' OR page LIKE '%/guias/%' THEN 'n/a'
            WHEN page LIKE '%proprietario.quintoandar%' OR page LIKE '%help.quintoandar%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br/auth%' OR page LIKE 'https://www.quintoandar.com.br/tenants%' THEN 'n/a'
            WHEN page LIKE '%/regioes-atendidas%' OR page LIKE '%br/condominio%' OR page LIKE '%br/morar%' THEN 'n/a' 
            WHEN page LIKE '%.br/imovel/%' OR page LIKE '%.br/apartamento%' THEN 'n/a'
            WHEN page LIKE 'https://www.quintoandar.com.br/' OR page LIKE 'https://www.quintoandar.com.br' THEN 'n/a'
            WHEN page LIKE '%com.br/s/%' THEN '2 filtros'
            WHEN RLIKE(page, 'com.br/.*/.*/.*/.*/.*/.*/.*') THEN '4+ filtros'
            WHEN RLIKE(page, 'com.br/.*/.*/.*/.*/.*/.*') THEN '3 filtros'
            WHEN RLIKE(page, 'com.br/.*/.*/.*/.*/.*') THEN '2 filtros'
            WHEN RLIKE(page, 'com.br/.*/.*/.*/.*') THEN '1 filtro'
            WHEN RLIKE(page, 'com.br/.*/.*/.*') THEN 'sem filtro'
            ELSE 'Other'
            END AS quantidade_de_filtros
    FROM
        layer1
)
SELECT
    site_url,
    device,
    page,
    query,
    country,
    domain,
    slug,
    subtitle_content,
    regiao_busca AS search_region,
    caminho_da_pagina AS page_path,
    estado AS state,
    cidades AS city,
    cluster_de_paginas AS page_cluster,
    estruturas AS structure,
    nivel_localizacao AS location_level,
    street_abbreviations,
    tipo_poi AS poi_type,
    combinacao_de_filtros AS filter_combination,
    filtro AS filter,
    filtro_condo AS condo_filter,
    filtro_house_char house_char_filter,
    filtro_house_type AS house_type_filter,
    filtro_1 AS filter_1,
    CASE
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/varanda-gourmet') THEN '/varanda-gourmet'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/varanda') THEN '/varanda'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/apartamento-cobertura') THEN '/apartamento-cobertura'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/ar-condicionado') THEN '/ar-condicionado'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/elevador') THEN '/elevador'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/piscina') THEN '/piscina'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/portaria-24h') THEN '/portaria-24h'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/academia') THEN '/academia'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/proximo-ao-metro') THEN '/proximo-ao-metro'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/aceita-pets') THEN '/aceita-pets'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/mobiliado') THEN '/mobiliado'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/originals') THEN '/originals'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/armarios-na-cozinha') THEN '/armarios-na-cozinha'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/armarios-no-quarto') THEN '/armarios-no-quarto'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/de-.*-a-.*-m2') THEN '/de-.*-a-.*-m2'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'(/de-.*-a-.*-venda)|(/de-.*-a-.*-aluguel)') THEN '/de-.*-a-.*-aluguel|-venda'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/.*-vagas') THEN '/.*-vagas'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/.*-banheiros') THEN '/.*-banheiros'
        WHEN REGEXP_LIKE(quantidade_de_filtros,'filtros') AND REGEXP_LIKE(page,'/.*-quartos') THEN '/.*-quartos'
        WHEN REGEXP_LIKE(page,'/s/') THEN '/s/'
    ELSE 'n/a'
    END AS filter_2,
    lp_sem_filtro AS lp_wo_filter,
    quantidade_de_filtros AS filter_count,
    is_branded,
    ctr,
    clicks,
    position,
    impressions,
    posimp,
    dt_created,
    year,
    month,
    day
FROM
    layer2
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36