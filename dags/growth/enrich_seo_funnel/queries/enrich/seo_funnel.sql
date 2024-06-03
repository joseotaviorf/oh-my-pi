WITH 
visit_schedule_confirmed_events AS (
    SELECT 
        id_user,
        id_amplitude,
        utm_source,
        ts_event, 
        entrance_uri, 
        referrer,
        LOWER(business_context) AS business_context,
        visit_code
    FROM 
        datalake_online_attribution.online_attribution 
    WHERE 
        DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND event_type_sanitized = 'visit_schedule_confirmed'
),
debug_visit_schedule_confirmed_events AS (
    SELECT
        id_user,
        id_amplitude,
        utm_source,
        ts_event, 
        entrance_uri, 
        referrer,
        LOWER(business_context) AS business_context,
        visit_code
    FROM 
        datalake_online_attribution.online_attribution 
    WHERE 
        DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND event_type_sanitized = 'debug_visit_schedule_confirmed'
),
extra_debug AS (
    SELECT
        d.id_user,
        d.id_amplitude,
        d.utm_source,
        d.ts_event, 
        d.entrance_uri, 
        d.referrer,
        d.business_context,
        d.visit_code
    FROM 
        visit_schedule_confirmed_events as v
        RIGHT JOIN debug_visit_schedule_confirmed_events as d
            ON v.visit_code = d.visit_code AND v.id_user = d.id_user
    WHERE 
        v.visit_code IS NULL
),
cross_platform AS (
    SELECT
        id_user,
        id_amplitude,
        utm_source,
        ts_event, 
        entrance_uri, 
        referrer,
        business_context,
        visit_code,
        ROW_NUMBER() OVER (PARTITION BY visit_code ORDER BY ts_event) AS rn_visit_code
    FROM 
        visit_schedule_confirmed_events  
    UNION ALL
    SELECT
        id_user,
        id_amplitude,
        utm_source,
        ts_event, 
        entrance_uri, 
        referrer,
        business_context,
        visit_code,
        ROW_NUMBER() OVER (PARTITION BY visit_code ORDER BY ts_event) AS rn_visit_code
    FROM 
        extra_debug
),
amplitude_visit AS (
    SELECT
        id_user,
        id_amplitude,
        utm_source,
        ts_event, 
        entrance_uri, 
        referrer,
        business_context,
        visit_code
    FROM 
        cross_platform
    WHERE 
        rn_visit_code = 1
        AND visit_code IS NOT NULL
),
tof AS (
    SELECT
        ui.id_tof_user AS id_user,
        ui.id_tof_user AS id_amplitude,
        ui.utm_source,
        ui.dt_event, 
        ui.entrance_uri, 
        ui.referrer,
        dr.city_group,
        ui.mkt_origin,
        LOWER(ui.business_context) AS business_context,
        TRUE AS is_tof,
        FALSE AS is_first_booking,
        FALSE AS is_booking
    FROM 
        datalake_top_of_funnel_demand.user_interactions AS ui
        LEFT JOIN dw_public.dim_region AS dr
        ON CAST(ui.sk_region AS INT) = dr.sk_region
    WHERE 
        DATE(dt_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND mkt_medium LIKE '%SEO%'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
rent_booking AS (
    SELECT
        av.id_user,
        av.id_amplitude,
        av.utm_source,
        DATE(av.ts_event) dt_event, 
        av.entrance_uri, 
        av.referrer,
        pmmd.city_group,
        pmmd.mkt_origin,
        LOWER(av.business_context) AS business_context,
        FALSE AS is_tof,
        CASE 
            WHEN pmmd.tenant_prospect_order = 1 THEN TRUE 
            ELSE FALSE 
        END AS is_first_booking,
        TRUE as is_booking
    FROM 
        amplitude_visit AS av
        LEFT JOIN datalake_ebdb_clean.visit AS v
            ON v.code = av.visit_code    
        LEFT JOIN dw_public.dim_booking AS b
            ON b.id_visit = v.id
        LEFT JOIN dw_datamarts.performance_marketing_metrics_demand AS pmmd --TENTAR SUBSTITUIR
            ON b.sk_booking = pmmd.sk_booking
    WHERE 
        av.business_context IN ('rent', 'RENT')
        AND pmmd.mkt_medium LIKE '%SEO%'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
sale_booking AS (
SELECT
    av.id_user,
    av.id_amplitude,
    av.utm_source,
    DATE(av.ts_event) dt_event, 
    av.entrance_uri, 
    av.referrer,
    pmmd.city_group,
    pmmd.mkt_origin,
    LOWER(av.business_context) AS business_context,
    FALSE AS is_tof,
    CASE 
        WHEN pmmd.buyer_prospect_order = 1 THEN TRUE 
        ELSE FALSE 
    END AS is_first_booking,
    TRUE as is_booking
    FROM 
        amplitude_visit AS av
        LEFT JOIN datalake_ebdb_clean.visit AS v
            ON v.code = av.visit_code    
        LEFT JOIN dw_public.dim_booking AS b
            ON b.id_visit = v.id
        LEFT JOIN dw_datamarts.sale_performance_marketing_metrics_demand AS pmmd --TENTAR SUBSTITUIR
            ON b.sk_booking = pmmd.sk_booking
WHERE 
    av.business_context IN ('sale', 'SALE')
    AND pmmd.mkt_medium LIKE '%SEO%'
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
aux_funnel AS (
    SELECT 
        *
    FROM 
        tof
    UNION ALL
    SELECT 
        *
    FROM 
        rent_booking
    UNION ALL
    SELECT 
        *
    FROM 
        sale_booking
),
seo_funnel AS (
    SELECT
        t.id_user,
        t.id_amplitude,
        t.utm_source,
        dt_event, 
        t.entrance_uri, 
        t.referrer,
        t.city_group,
        t.mkt_origin,
        t.business_context,
        MAX(is_tof) AS is_tof,
        MAX(is_booking) AS is_booking,
        MAX(is_first_booking) AS is_first_booking
    FROM 
        aux_funnel AS t
    WHERE t.entrance_uri IS NOT NULL
    GROUP BY 1,2,3,4,5,6,7,8,9
)
SELECT
    COALESCE (id_user, id_amplitude) AS id_user,
    COALESCE(city_group, 'Not Mapped') AS city_group,
    mkt_origin,
    business_context,
    CASE 
        WHEN 
            entrance_uri LIKE '%/alugar/%' 
            OR entrance_uri LIKE '%/comprar/%'
            OR entrance_uri LIKE '%/imovel/%'
        THEN 'Transacional'
        WHEN 
            entrance_uri LIKE '%/regioes-atendidas%'
            OR entrance_uri LIKE '%br/condominio%'
            OR entrance_uri LIKE '%br/morar%'
            OR entrance_uri LIKE '%/guias/%'
        THEN 'Informacional'
        WHEN 
            entrance_uri LIKE 'https://www.quintoandar.com.br/' 
            OR entrance_uri LIKE 'https://www.quintoandar.com.br'
        THEN 'Home'
        ELSE 'Other'
    END AS structure,
    CASE
        WHEN 
            entrance_uri LIKE '%/alugar/%' 
        THEN 'Busca aluguel'
        WHEN
            entrance_uri LIKE '%/comprar/%' 
        THEN 'Busca compra'
        WHEN 
            entrance_uri LIKE '%/regioes-atendidas%' 
        THEN 'Regiões atendidas'
        WHEN 
            entrance_uri LIKE '%br/condominio/%' 
        THEN 'Condomínio'
        WHEN 
            entrance_uri LIKE '%br/apartamento/%'
            OR entrance_uri LIKE '%br/imovel/%'
        THEN 'Listing'
        WHEN 
            entrance_uri LIKE '%br/morar/%' 
        THEN 'Regiões atendidas'
        WHEN 
            entrance_uri LIKE '%/guias/%'
        THEN 'Guias'
        WHEN 
            entrance_uri LIKE 'https://www.quintoandar.com.br/' 
            OR entrance_uri LIKE 'https://www.quintoandar.com.br'
        THEN 'Home'
        ELSE 'Other'
    END AS page_cluster,
    CASE
        WHEN 
            entrance_uri LIKE 'https://www.quintoandar.com.br/'
            OR entrance_uri LIKE 'https://www.quintoandar.com.br/auth%'
            OR entrance_uri LIKE 'https://www.quintoandar.com.br/tenants%'
        THEN 'n/a'
        WHEN 
            entrance_uri LIKE '%.com.br/imovel/%'
            OR entrance_uri LIKE '%.com.br/apartamento/%'
        THEN 'Imóveis'
        WHEN 
            entrance_uri LIKE '%br/condominio%' 
            AND entrance_uri REGEXP '/r.-|/r-|/rua-|/alameda-|/av.-|/av-|/avenida-|/tv.-|/tv-|/travessa-|/servidao-|/rod.-|/estrada-|/estr.-' 
        THEN 'Endereço Condomínio'
        WHEN 
            entrance_uri LIKE '%br/condominio%'
        THEN 'Nome Condomínio'
        WHEN 
            entrance_uri LIKE '%br/morar/%' 
        THEN 'Cidades'
        WHEN 
            entrance_uri REGEXP '/r.-|/r-|/rua-|/alameda-|/av.-|/av-|/avenida-|/tv.-|/tv-|/travessa-|/servidao-|/rod.-|/estrada-|/estr.-'
        THEN 'Ruas'
        WHEN
            entrance_uri LIKE '%/zona-%'
        THEN 'Zonas'
        WHEN
            entrance_uri REGEXP '/alvorada-rs-brasil|/americana-sp-brasil|/aparecida-de-goiania-go-brasil|/barueri-sp-brasil|/belford-roxo-rj-brasil|/belo-horizonte-mg-brasil|/belo-horizonte-bh-brasil|/belem-pa-brasil|/betim-mg-brasil|/brasilia-df-brasil|/campinas-sp-brasil|/canoas-rs-brasil|/carapicuiba-sp-brasil|/ciudad-de-mexico-cdmx-brasil|/contagem-mg-brasil|/contagem-bh-brasil|/cotia-sp-brasil|/curitiba-pr-brasil|/diadema-sp-brasil|/duque-de-caxias-rj-brasil|/embu-das-artes-sp-brasil|/ferraz-de-vasconcelos-sp-brasil|/florianopolis-sc-brasil|/fortaleza-ce-brasil|/goiania-go-brasil|/gravatai-rs-brasil|/guaruja-sp-brasil|/guarulhos-sp-brasil|/hortolandia-sp-brasil|/indaiatuba-sp-brasil|/itaquaquecetuba-sp-brasil|/jaboatao-dos-guararapes-pe-brasil|/jacarei-sp-brasil|/jundiai-sp-brasil|/manaus-am-brasil|/maua-sp-brasil|/mesquita-rj-brasil|/mogi-das-cruzes-sp-brasil|/naucalpan-de-juarez-em-brasil|/nilopolis-rj-brasil|/niteroi-rj-brasil|/nova-iguacu-rj-brasil|/nova-lima-mg-brasil|/novo-hamburgo-rs-brasil|/osasco-sp-brasil|/palhoca-sc-brasil|/paulinia-sp-brasil|/pinhais-pr-brasil|/porto-alegre-rs-brasil|/poa-sp-brasil|/praia-grande-sp-brasil|/recife-pe-brasil|/ribeirao-das-neves-mg-brasil|/ribeirao-pires-sp-brasil|/ribeirao-preto-sp-brasil|/rio-de-janeiro-rj-brasil|/salvador-ba-brasil|/santana-de-parnaiba-sp-brasil|/santo-andre-sp-brasil|/santos-sp-brasil|/sorocaba-sp-brasil|/sumare-sp-brasil|/suzano-sp-brasil|/sao-bernardo-do-campo-sp-brasil|/sao-caetano-do-sul-sp-brasil|/sao-goncalo-rj-brasil|/sao-jose-dos-pinhais-pr-brasil|/sao-jose-sc-brasil|/sao-jose-do-rio-preto-sp-brasil|/sao-jose-dos-campos-sp-brasil|/sao-leopoldo-rs-brasil|/sao-paulo-sp-brasil|/sao-vicente-sp-brasil|/taboao-da-serra-sp-brasil|/taubate-sp-brasil|/uberlandia-mg-brasil|/valinhos-sp-brasil|/viamao-rs-brasil|/vila-velha-es-brasil|/vinhedo-sp-brasil|/vitoria-es-brasil|/votorantim-sp-brasil|/varzea-paulista-sp-brasil' 
        THEN 'Cidades'
        WHEN
            entrance_uri REGEXP 'shopping-|/metro-|escola-|cinema-|/mercado-|universidade-|academia-|hospital-|instituto-|/sh-|/estacao-|/espaco-|faculdade-|farmacia-|/galeria-|fundacao-|museu-|loja-|/terminal-|shopping-|teatro-|universitaria|/unidade-de-|ufrj|uff|uerj|unb|unicamp|uerj|/uci-|drogaria-|ufabc-|ufmg-|supermercado|cozinha-|colegio-|creche-|conjunto-|lanches-|habitacoes-|sesc-|senac-|restaurante-|/praca-|condominio-|/conj.-hab.-|/conj.-res.-|/conj.-res.-|confeitaria-|cinema-|churrascaria|sushi|pizza|/centro-medico-|centro-universitario|centro-de-saude|centro-de-tradicoes|centro-medico|centro-comercial|/arena-|crossfit|ambulatorio|aeroporto-'
        THEN 'POI'
        WHEN
            entrance_uri LIKE '%.com.br/s/%' 
            AND entrance_uri REGEXP '-sao-paulo-sp|-fortaleza-ce|-rio-de-janeiro-rj|-campinas-sp|-porto-alegre-rs|-santo-andre-sp|-belo-horizonte-mg|-novo-hamburgo-rs|-salvador-ba|-osasco-sp|-niteroi-rj|-curitiba-pr|-santos-sp|-sao-jose-dos-pinhais-pr|-florianopolis-sc|-sao-caetano-do-sul-sp'
        THEN 'Cidades'
        WHEN
            entrance_uri LIKE '%-brasil' 
            OR entrance_uri LIKE '%-brasil/%' 
            OR entrance_uri LIKE '%-brasil-%' 
            OR entrance_uri LIKE '%-brasil?%'
        THEN 'Bairros'
        ELSE 'POI'
    END AS location_level,
    CASE
        WHEN 
            entrance_uri LIKE '%/regioes-atendidas%'
            OR entrance_uri LIKE '%br/condominio%'
            OR entrance_uri LIKE '%br/morar%'
            OR entrance_uri LIKE '%/guias/%'
            OR entrance_uri LIKE '%.com.br/imovel/%'
        THEN 'n/a'
        WHEN
            RLIKE(entrance_uri, 'com.br/.*/.*/.*/.*/.*/.*/.*') 
        THEN '4+ filtros'
        WHEN
            RLIKE(entrance_uri, 'com.br/.*/.*/.*/.*/.*/.*') 
        THEN '3 filtros'
        WHEN
            entrance_uri LIKE '%.com.br/s/%' 
            OR RLIKE(entrance_uri, 'com.br/.*/.*/.*/.*/.*')
        THEN '2 filtros'
        WHEN
            RLIKE(entrance_uri, 'com.br/.*/.*/.*/.*') 
        THEN '1 filtro'
        WHEN
            entrance_uri LIKE 'https://www.quintoandar.com.br/' 
            OR RLIKE(entrance_uri, 'com.br/.*/.*/.*')
        THEN 'sem filtro'
        ELSE 'Other'
    END AS filters_count,
    CASE
        WHEN 
            entrance_uri LIKE 'https://www.quintoandar.com.br/' 
            OR entrance_uri LIKE 'https://www.quintoandar.com.br/auth%'
            OR entrance_uri LIKE 'https://www.quintoandar.com.br/tenants%'
            OR entrance_uri LIKE '%com.br/imovel/%'
            OR entrance_uri LIKE '%/regioes-atendidas%'
            OR entrance_uri LIKE '%br/condominio%'
            OR entrance_uri LIKE '%br/morar%'
            OR entrance_uri LIKE '%/guias/%'
            OR entrance_uri LIKE '%.com.br/apartamento/%'
        THEN 'n/a'
        WHEN 
            entrance_uri REGEXP '/apartamento|/apartamento-cobertura|/casacondominio|/casa|/kitnet' 
            AND entrance_uri REGEXP '/academia|/elevador|/piscina|/portaria-24h|/proximo-ao-metro' 
            AND entrance_uri REGEXP '-quartos|-banheiros|-vagas|-venda|-aluguel|-m2|/ar-condicionado|/varanda|/varanda-gourmet|/mobiliado|/armarios-na-cozinha|/armarios-no-quarto|/aceita-pets' 
            AND entrance_uri NOT LIKE '%/academia-%' 
        THEN 'Tipo + Característica do Imóvel + Condomínio'
        WHEN 
            entrance_uri REGEXP '/apartamento|/apartamento-cobertura|/casacondominio|/casa|/kitnet' 
            AND entrance_uri REGEXP '-quartos|-banheiros|-vagas|-venda|-aluguel|-m2|/ar-condicionado|/varanda|/varanda-gourmet|/mobiliado|/armarios-na-cozinha|/armarios-no-quarto|/aceita-pets' 
        THEN 'Tipo + Característica do Imóvel'
        WHEN
            entrance_uri REGEXP '/apartamento|/apartamento-cobertura|/casacondominio|/casa|/kitnet' 
            AND entrance_uri REGEXP '/academia|/elevador|/piscina|/portaria-24h|/proximo-ao-metro' 
            AND entrance_uri NOT LIKE '%/academia-%' 
        THEN 'Tipo do Imóvel + Condomínio'
        WHEN
            entrance_uri REGEXP '/academia|/elevador|/piscina|/portaria-24h|/proximo-ao-metro' 
            AND entrance_uri REGEXP '-quartos|-banheiros|-vagas|-venda|-aluguel|-m2|/ar-condicionado|/varanda|/varanda-gourmet|/mobiliado|/armarios-na-cozinha|/armarios-no-quarto|/aceita-pets' 
            AND entrance_uri NOT LIKE '%/academia-%' 
        THEN 'Característica do Imóvel + Condomínio'
        WHEN
            entrance_uri REGEXP '/apartamento|/apartamento-cobertura|/casacondominio|/casa|/kitnet' 
        THEN 'Tipo do Imóvel' 
        WHEN
            entrance_uri REGEXP '-quartos|-banheiros|-vagas|-venda|-aluguel|-m2|/ar-condicionado|/varanda|/varanda-gourmet|/mobiliado|/armarios-na-cozinha|/armarios-no-quarto|/aceita-pets'
        THEN 'Característica do Imóvel' 
        WHEN
            entrance_uri REGEXP '/academia|/elevador|/piscina|/portaria-24h|/proximo-ao-metro' 
            AND entrance_uri NOT LIKE '%/academia-%' 
        THEN 'Condomínio'
        WHEN
            entrance_uri REGEXP '/originals' 
        THEN 'Originals'
        WHEN 
            entrance_uri REGEXP '/s/' 
        THEN 'Páginas com /s/'
        ELSE 'Other'
    END AS filter_combination,
    CASE
        WHEN 
            entrance_uri LIKE 'https://www.quintoandar.com.br/'
            OR entrance_uri LIKE 'https://www.quintoandar.com.br/auth%'
            OR entrance_uri LIKE 'https://www.quintoandar.com.br/tenants%'
            OR entrance_uri LIKE '%com.br/imovel/%'
            OR entrance_uri LIKE '%/regioes-atendidas%'
            OR entrance_uri LIKE '%br/condominio%'
            OR entrance_uri LIKE '%br/morar%'
            OR entrance_uri LIKE '%/guias/%'
            OR entrance_uri LIKE '%.com.br/apartamento/%'
        THEN 'n/a'
        WHEN CONTAINS(entrance_uri,'/apartamento') THEN 'Apartamento'
        WHEN CONTAINS(entrance_uri,'/casacondominio') THEN 'Casa Condomínio'
        WHEN CONTAINS(entrance_uri,'/casa') THEN 'Casa'
        WHEN CONTAINS(entrance_uri,'/kitnet') THEN 'Kitnet'
        WHEN CONTAINS(entrance_uri,'-quartos') THEN 'Quartos'
        WHEN CONTAINS(entrance_uri,'-banheiros') THEN 'Banheiros' 
        WHEN CONTAINS(entrance_uri,'-vagas') THEN 'Vagas'
        WHEN entrance_uri REGEXP '-venda|-aluguel' THEN 'Valor'
        WHEN CONTAINS(entrance_uri,'-m2') THEN 'Área'
        WHEN entrance_uri REGEXP '/mobiliado|/armarios-na-cozinha|/armarios-no-quarto' THEN 'Mobílias'
        WHEN CONTAINS(entrance_uri,'/aceita-pets') THEN 'Pets'
        WHEN CONTAINS(entrance_uri,'/proximo-ao-metro') THEN 'Metro'
        WHEN CONTAINS(entrance_uri,'/originals') THEN 'QuintoAndar Originals'
        WHEN entrance_uri REGEXP '/academia|/elevador|/piscina|/portaria-24h' AND entrance_uri NOT LIKE '%/academia-%' THEN 'Condomínio'
        WHEN entrance_uri REGEXP '/ar-condicionado|/varanda|/varanda-gourmet' THEN 'Comodidades'
        WHEN CONTAINS(entrance_uri,'/s/') AND entrance_uri REGEXP '-apartamento|-apto' THEN 'Apartamento'
        WHEN CONTAINS(entrance_uri,'/s/') AND CONTAINS(entrance_uri,'-casa') THEN 'Casa'
        WHEN CONTAINS(entrance_uri,'/s/') AND CONTAINS(entrance_uri,'-kitnet-ou-studio') THEN 'Kitnet'
        ELSE 'Other'   
    END AS filter_1,
    CASE 
        WHEN referrer LIKE '%google%' OR referrer LIKE '%bing%' THEN FALSE 
        ELSE TRUE
    END AS is_attribution,
    is_tof,
    is_booking,
    is_first_booking,
    dt_event,
    YEAR(dt_event) AS year,
    MONTH(dt_event) AS month,
    DAY(dt_event) AS day
FROM 
    seo_funnel
WHERE
    DATE(dt_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15