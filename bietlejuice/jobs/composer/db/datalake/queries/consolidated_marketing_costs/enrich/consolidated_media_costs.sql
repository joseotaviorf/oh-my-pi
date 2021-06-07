-- Union of medias
WITH medias_consolidated AS (
    -- GOOGLE
    SELECT
        id_date,
        'google' AS origin,
        campaign_name,
        campaign_city,
        account_name,
        report_type,
        ad_type,
        utm_term,
        utm_content,
        utm_campaign,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost
    FROM
        datalake_consolidated_marketing_costs.google_consolidated_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    
    -- CRITEO
    UNION ALL

    SELECT
        id_date,
        'criteo' AS origin,
        campaign_name,
        NULL AS campaign_city,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        0.0 AS desktop_cost,
        0.0 AS mobile_cost,
        other_cost,
        total_cost
    FROM
        datalake_consolidated_marketing_costs.criteo_consolidated_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))

    -- RTB
    UNION ALL

    SELECT
        id_date,
        'rtb' AS origin,
        campaign_name,
        NULL AS campaign_city,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        0.0 AS desktop_cost,
        0.0 AS mobile_cost,
        other_cost,
        total_cost
    FROM
        datalake_consolidated_marketing_costs.rtb_consolidated_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))

    -- MITULA
    UNION ALL

    SELECT
        id_date,
        'mitula' AS origin,
        campaign_name,
        NULL AS campaign_city,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost
    FROM
        datalake_consolidated_marketing_costs.mitula_consolidated_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
),

shared_consolidated_costs AS (
    SELECT
        mc.id_date,
        origin,
        campaign_name,
        campaign_city,
        account_name,
        utm_campaign,
        utm_term,
        utm_content,
        desktop_cost * COALESCE(sr.share, 1) AS desktop_cost,
        mobile_cost * COALESCE(sr.share, 1) AS mobile_cost,
        other_cost * COALESCE(sr.share, 1) AS other_cost,
        total_cost * COALESCE(sr.share, 1) AS total_cost,
        report_type,
        ad_type
    FROM
        medias_consolidated mc
        LEFT JOIN datalake_marketing_costs_sharing_rules.old_sharing_rules sr
            ON mc.id_date = sr.id_date 
            AND split(mc.campaign_name, '\\.')[0] = sr.id_rule
),

-- Next CTE is going to be deprecated soon
-- For more information access
-- https://docs.google.com/presentation/d/1YnqR-ypPI58I_Q1Re3VljXQqlP6XlUzfcvInxFFlUZw/edit#slide=id.gcd7c7ea5b9_0_0

city_group_mappings AS (
    SELECT DISTINCT
        mc.campaign_name,
        CASE 
            WHEN LOWER(mc.campaign_name) IN (
                    'florianópolis', 'curitiba', 'goiânia', 
                    'rio de janeiro', 'rmsp', 'belo horizonte', 
                    'brasília', 'campinas', 'porto alegre', 
                    'santos', 'recife', 'salvador', 
                    'são josé dos campos', 'mogi das cruzes', 'vitória', 
                    'itapecerica da serra', 'cotia', 'sorocaba', 
                    'ribeirão preto'
                ) THEN LOWER(mc.campaign_name)
            WHEN LOWER(mc.campaign_name) LIKE '%campinas%' THEN 'Campinas'
            WHEN LOWER(mc.campaign_name) LIKE '%s_o_paulo%'OR LOWER(mc.campaign_name) LIKE '%sp detailed%' THEN'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE 'sp %' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%all cities%' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%rmsp%' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%guarulhos%' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%abc%' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%barueri%' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%osasco%' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%jundia%' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%santo_andr%' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%s_o_bernardo%' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%s_o_caetano%' THEN 'RMSP'
            WHEN LOWER(mc.campaign_name) LIKE '%cotia%' THEN 'Cotia'
            WHEN LOWER(mc.campaign_name) LIKE '%rio%de%janeiro%' THEN 'Rio de Janeiro'
            WHEN LOWER(mc.campaign_name) LIKE '%niter_i%' THEN 'Rio de Janeiro'
            WHEN LOWER(mc.campaign_name) LIKE '%bh%'OR LOWER(mc.campaign_name) LIKE '%belo%h%' THEN 'Belo Horizonte'
            WHEN LOWER(mc.campaign_name) LIKE '%minas_gerais%' THEN 'Belo Horizonte'
            WHEN LOWER(mc.campaign_name) LIKE '%goi_nia%' OR LOWER(mc.campaign_name) LIKE '%goi_s%' THEN 'Goiânia'
            WHEN LOWER(mc.campaign_name) LIKE '%bras_lia%' OR LOWER(mc.campaign_name) LIKE '%distrito_federal%' THEN 'Brasília'
            WHEN LOWER(mc.campaign_name) LIKE '%porto%alegre%' THEN 'Porto Alegre'
            WHEN LOWER(mc.campaign_name) LIKE '%curitiba%' OR LOWER(mc.campaign_name) LIKE '%paran_%' THEN 'Curitiba'
            WHEN LOWER(mc.campaign_name) LIKE '%florian_polis%' OR LOWER(mc.campaign_name) LIKE '%santa_catarina%' THEN 'Florianópolis'
            WHEN LOWER(mc.campaign_name) LIKE '%poa%' THEN 'Porto Alegre'
            WHEN LOWER(mc.campaign_name) LIKE '%ctba%' THEN 'Curitiba'
            WHEN LOWER(mc.campaign_name) LIKE '%fln%' THEN 'Florianópolis'
            WHEN LOWER(mc.campaign_name) LIKE '%cps%' THEN 'Campinas'
            WHEN LOWER(mc.campaign_name) LIKE '%bsb%' THEN 'Brasília'
            WHEN LOWER(mc.campaign_name) LIKE '%rj%' THEN 'Rio de Janeiro'
            WHEN LOWER(mc.campaign_name) LIKE '%santos%' THEN 'Santos'
            WHEN LOWER(mc.campaign_name) LIKE '%recife%' THEN 'Recife'
            WHEN LOWER(mc.campaign_name) LIKE '%salvador%' THEN 'Salvador'
            WHEN LOWER(mc.campaign_name) LIKE '%sjc%' THEN 'São José dos Campos'
            WHEN LOWER(mc.campaign_name) LIKE '%mogi%' THEN 'Mogi das Cruzes'
            WHEN LOWER(mc.campaign_name) LIKE '%vix%' THEN 'Vitória'
            WHEN LOWER(mc.campaign_name) LIKE '%itapecerica%' THEN 'Itapecerica da Serra'
            WHEN LOWER(mc.campaign_name) LIKE '%sorocaba%' THEN 'Sorocaba'
            WHEN LOWER(mc.campaign_name) LIKE '%ribeir_o%preto%' THEN 'Ribeirão Preto'
        END AS city_group_by_campaign_name,
        CASE 
            WHEN campaign_city IN (
                    'Florianópolis', 'Curitiba', 'Goiânia',
                    'Rio de Janeiro', 'RMSP', 'Belo Horizonte', 
                    'Brasília', 'Campinas', 'Porto Alegre', 
                    'Santos', 'Recife', 'Salvador', 
                    'São José dos Campos', 'Mogi das Cruzes', 'Vitória', 
                    'Itapecerica da Serra', 'Cotia', 'Sorocaba', 
                    'Ribeirão Preto'
                ) THEN campaign_city
            WHEN campaign_city = 'campinas' THEN 'Campinas'
            WHEN campaign_city IN (
                    'sp', 'jui', 'santo_andre', 
                    'guarulhos', 'osasco', 'sao_caetano', 
                    'sao_bernardo', 'barueri', 'rmsp'
                ) THEN 'RMSP'
            WHEN campaign_city IN (
                    'rj', 'niteroi', 'rio_de_janeiro', 
                    'rio'
                ) THEN 'Rio de Janeiro'
            WHEN campaign_city IN ('bh', 'belo_horizonte') THEN 'Belo Horizonte'
            WHEN campaign_city = 'goiania' THEN 'Goiânia'
            WHEN campaign_city IN ('poa', 'porto_alegre') THEN 'Porto Alegre'
            WHEN campaign_city = 'curitiba' THEN 'Curitiba'
            WHEN campaign_city IN ('fln', 'florianopolis') THEN 'Florianópolis'
            WHEN campaign_city IN ('bsb', 'brasilia') THEN 'Brasília'
            WHEN campaign_city = 'santos' THEN 'Santos'
            WHEN campaign_city = 'recife' THEN 'Recife'
            WHEN campaign_city = 'salvador' THEN 'Salvador'
            WHEN campaign_city IN ('sjc', 'sao_jose_dos_campos') THEN 'São José dos Campos'
            WHEN campaign_city IN ('mogi', 'mogi_das_cruzes') THEN 'Mogi das Cruzes'
            WHEN campaign_city IN ('vitoria', 'vix') THEN 'Vitória'
            WHEN campaign_city IN ('itapecerica', 'itapecerica_da_serra') THEN 'Itapecerica da Serra'
            WHEN campaign_city = 'cotia'THEN 'Cotia'
            WHEN campaign_city = 'sorocaba'THEN 'Sorocaba'
            WHEN campaign_city IN ('ribeirao_preto', 'ribeiraopreto') THEN 'Ribeirão Preto'
        END AS city_group_by_campaign_convention,
        manual_cities.city_group AS city_group_by_manual_convention
    FROM
        medias_consolidated mc
        LEFT JOIN datalake_gsheets_clean.marketing_manual_campaign_cities manual_cities
            ON LOWER(mc.campaign_name) = LOWER(manual_cities.campaign_name)
)

SELECT 
    id_date,
    origin,
    scc.campaign_name,
    COALESCE(
        cgm.city_group_by_manual_convention,
        cgm.city_group_by_campaign_name, 
        cgm.city_group_by_campaign_convention,
        'Not Mapped'
    ) AS city_group,
    account_name,
    utm_campaign,
    utm_term,
    utm_content,
    desktop_cost,
    mobile_cost,
    other_cost,
    total_cost,
    report_type,
    ad_type
FROM 
    shared_consolidated_costs scc
    LEFT JOIN city_group_mappings cgm
      ON scc.campaign_name = cgm.campaign_name
