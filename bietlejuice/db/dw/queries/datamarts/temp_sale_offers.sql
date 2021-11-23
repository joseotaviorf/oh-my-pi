WITH giroffer AS (
    SELECT 
        id AS sk_offer,
        id_buyer AS sk_buyer,
        id_house AS sk_house,
        id_owner AS sk_owner,
        ts_created AS ts_offer_created,
        last_price_offered_by_buyer
    FROM 
        datalake_firestore_prod.sale_offer fso
),
visits AS (
    SELECT
        fv.sk_buyer,
        fv.sk_house,
        fv.sk_user_agent,
        fv.sk_visit_completed_date,
        db.dt_created AS ts_booking_created_date
    FROM 
        sale.fact_visits AS fv
    INNER JOIN
        dim_booking AS db
            ON db.sk_booking = fv.sk_booking
),
visits_before_offer AS (
    WITH aux AS (
        SELECT
            g.sk_offer,
            v.sk_user_agent,
            du.nome AS agent_name,
            ts_booking_created_date,
            ROW_NUMBER() OVER (PARTITION BY g.sk_offer,g.sk_house,g.sk_buyer ORDER BY v.ts_booking_created_date DESC) AS rw_visit_completed
        FROM 
            giroffer AS g
        INNER JOIN 
            visits v ON
                v.sk_buyer = g.sk_buyer 
                AND v.sk_house = g.sk_house
                AND v.sk_visit_completed_date>0
                AND v.ts_booking_created_date < g.ts_offer_created
        INNER JOIN 
            dim_user AS du
                ON du.id = v.sk_user_agent
    )   
    SELECT * FROM aux WHERE rw_visit_completed = 1
),
booking_before_offer AS (
    WITH aux AS (
        SELECT
            g.sk_offer,
            v.sk_user_agent,
            du.nome AS agent_name,
            ts_booking_created_date,
            ROW_NUMBER() OVER (PARTITION BY g.sk_offer,g.sk_house,g.sk_buyer ORDER BY v.ts_booking_created_date DESC) AS rw_booking
        FROM 
            giroffer AS g
        INNER JOIN
            visits AS v
                ON v.sk_buyer = g.sk_buyer 
                AND v.sk_house = g.sk_house
                AND v.ts_booking_created_date < g.ts_offer_created
        INNER JOIN 
            dim_user AS du
                ON du.id = v.sk_user_agent
    )   
    SELECT 
        *
    FROM 
        aux
    WHERE 
        rw_booking = 1
),
relation_booking_offer AS (
    SELECT 
        g.sk_offer,
        COALESCE(vbr.ts_booking_created_date,bbr.ts_booking_created_date) AS ts_booking_created_date,
        COALESCE(vbr.sk_user_agent,bbr.sk_user_agent,-1) AS sk_user_agent,
        COALESCE(vbr.agent_name,bbr.agent_name) AS agent_name
    FROM 
        giroffer AS g
    LEFT JOIN 
        visits_before_offer AS vbr
            ON vbr.sk_offer = g.sk_offer
    LEFT JOIN 
        booking_before_offer AS bbr
            ON bbr.sk_offer = g.sk_offer
),
work_contract AS (
    WITH contract_aud AS (
        SELECT
            agent_id,
            du.id AS user_id,
            contract.contract_name AS contract_name,
            "timestamp",
            du.dadosagente_ativo,
            RANK() OVER (PARTITION BY agent_id ORDER BY timestamp DESC) AS r
        FROM
            agent.agent_contract AS ac
        JOIN
            dim_user AS du
                ON du.dados_agente_id = ac.agent_id
        LEFT JOIN
            datalake_ebdb_clean_prod.work_contract AS contract 
                ON ac.workcontract_id = contract.id
        WHERE contract_name IS NOT NULL
    ),
    actual_contract AS (
    SELECT
        agent_id,
        contract_name
    FROM 
        contract_aud
    WHERE r = 1
    ),
    base_agents AS (
    SELECT
        ca.*,
        LAG(ca.contract_name) OVER(PARTITION BY ca.agent_id ORDER BY ca.r DESC) AS previous_work_contract,
        ac.contract_name AS actual_contract
    FROM 
        contract_aud AS ca
    LEFT JOIN
        actual_contract AS ac
            ON ac.agent_id = ca.agent_id
    ORDER BY 1, r DESC
    )
    SELECT
        agent_id as sk_agent,
        user_id as sk_user_agent,
        actual_contract,
        contract_name,
        previous_work_contract,
        "timestamp" as ts_work_contract_start,
        LEAD(timestamp) over(partition by agent_id order by r desc) as ts_work_contract_end,
        dadosagente_ativo,
        r
    FROM 
        base_agents
    WHERE 
        previous_work_contract <> contract_name 
        OR previous_work_contract IS NULL
    ORDER BY 1, r DESC
),
vendas_flow_type AS (
    WITH last_sf_entry AS (
        SELECT 
            ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS row,
            id,
            flow_type
        FROM datalake_sales_flow_clean_prod.sales_flow
    )
    SELECT 
        o.id_firestore AS sk_offer,
        sf.flow_type
    FROM 
        datalake_sales_flow_clean_prod.offer AS o
    INNER JOIN
        last_sf_entry AS sf
            ON sf.id = o.id_sales_flow AND sf.row=1
    GROUP BY 1,2
),
 vendas_offers AS (
    WITH last_offer_entry AS (
        SELECT 
            ROW_NUMBER() OVER (PARTITION BY id_firestore ORDER BY ts_updated DESC) AS row,
            *
        FROM 
            datalake_sales_flow_clean_prod.offer
    )
    SELECT 
        id_firestore AS sk_offer,
        status,
        ts_accepted,
        ts_discarded,
        id_sales_flow
    FROM 
        last_offer_entry
    WHERE row =1
),
vendas_specialists AS (
    WITH last_specialist AS (
        SELECT 
            ROW_NUMBER() OVER (PARTITION BY id_sales_flow,kind ORDER BY ts_updated DESC) AS row,
            *
        FROM 
            datalake_sales_flow_clean_prod.specialist
    ),
    offers AS (    
        SELECT 
            id_firestore AS sk_offer,
            id_sales_flow
        FROM 
            datalake_sales_flow_clean_prod.offer AS o
        GROUP BY 1,2
    )        
    SELECT 
        sk_offer,
        dm.id_main_user AS sk_user_deal_maker,
        dm.specialist_name AS deal_maker_name,
        dm.id_specialist AS sk_deal_maker,
        dm.email AS deal_maker_email,
        tl.specialist_name AS team_lead_name,
        tl.email AS team_lead_email,
        tl.id_main_user AS sk_user_team_lead,
        tl.id_specialist AS sk_team_lead, 
        
        CASE 
            WHEN deal_maker_email IN ('daniel.fernandes@corretores.quintoandar.com.br','eduardo.marcello@corretores.quintoandar.com.br','josue.junior@corretores.quintoandar.com.br',
            'karina.nAScimento@corretores.quintoandar.com.br','leandro.falveno@corretores.quintoandar.com.br','renato.lacerda@corretores.quintoandar.com.br','roberta.brisolla@corretores.quintoandar.com.br',
            'vinicius.dias@corretores.quintoandar.com.br','claudia.moraes@corretores.quintoandar.com.br','izidro.martins@corretores.quintoandar.com.br','julio.linhares@corretores.quintoandar.com.br',
            'leonardo.monteiro@corretores.quintoandar.com.br','rafael.maciel@corretores.quintoandar.com.br','raquel.xavier@corretores.quintoandar.com.br','silvana.sousa@corretores.quintoandar.com.br',
            'tiago.lopes@corretores.quintoandar.com.br') THEN true
            ELSE false 
        END AS is_offer_portfolio,
            
        CASE 
            WHEN deal_maker_email IN ('daniel.fernandes@corretores.quintoandar.com.br','eduardo.marcello@corretores.quintoandar.com.br','josue.junior@corretores.quintoandar.com.br',
            'karina.nAScimento@corretores.quintoandar.com.br','leandro.falveno@corretores.quintoandar.com.br','renato.lacerda@corretores.quintoandar.com.br','roberta.brisolla@corretores.quintoandar.com.br',
            'vinicius.dias@corretores.quintoandar.com.br') THEN to_date('2021-11-01','yyyy-mm-dd') 
            WHEN deal_maker_email IN ('claudia.moraes@corretores.quintoandar.com.br','izidro.martins@corretores.quintoandar.com.br','julio.linhares@corretores.quintoandar.com.br',
            'leonardo.monteiro@corretores.quintoandar.com.br','rafael.maciel@corretores.quintoandar.com.br','raquel.xavier@corretores.quintoandar.com.br','silvana.sousa@corretores.quintoandar.com.br',
            'tiago.lopes@corretores.quintoandar.com.br') THEN to_date('2021-11-04','yyyy-mm-dd')
        END AS offer_portfolio_start_date
        
    FROM 
        offers AS o
    LEFT JOIN 
        last_specialist AS dm 
        ON dm.id_sales_flow = o.id_sales_flow 
        AND dm.kind = 'DEAL_MAKER' 
        AND dm.row =1
    LEFT JOIN 
        last_specialist AS tl
        ON tl.id_sales_flow = o.id_sales_flow 
        AND tl.kind = 'TEAM_LEAD' 
        AND tl.row =1
),
vendas_ccvs AS (
    WITH last_ccv_entry AS (
        SELECT 
            ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated DESC) AS row,
            *
        FROM 
            datalake_sales_flow_clean_prod.ccv_flow
    ),
    offers AS (    
        SELECT 
            id_firestore AS sk_offer,
            id_sales_flow
        FROM 
            datalake_sales_flow_clean_prod.offer AS o
        GROUP BY 1,2
    )    
    SELECT 
        o.sk_offer,
        lce.ts_signed,
        lce.ts_created
    FROM 
        offers AS o
    LEFT JOIN
        vendas_specialists AS vs
            ON vs.sk_offer = o.sk_offer
    INNER JOIN 
        last_ccv_entry AS lce
            ON lce.id_sales_flow = o.id_sales_flow
            AND lce.row =1 
            AND ((lce.ts_signed::timestamp - lce.ts_created::timestamp)>0 OR (vs.sk_deal_maker IS NOT NULL AND lce.status = 'SIGNED' ))
),
monday_offers AS (
    WITH mo AS (
        SELECT 
            id_offer AS sk_offer,
            offer_status AS status,
            id_consultant AS sk_deal_maker,
            dt_accepted AS dt_offer_accepted,
            dt_offer_dismissed,
            dt_sale_agreement_created,
            dt_sale_agreement_signed,
            dt_sale_agreement_cancelled,
            REVERSE(REPLACE(REPLACE(SPLIT_PART(REVERSE(id_consultant),',',1),'[',''),']','')) AS last_id_consultant,
            sale_price_agreed
        FROM 
            datalake_firestore_prod.monday
    ),
    aux_users AS (
        SELECT 
            gmu.*,
            ROW_NUMBER() OVER (PARTITION BY gmu.id_monday) AS row
        FROM datalake_raw.gsheets_monday_users AS gmu
    )
    SELECT 
        mo.*,
        au.name AS deal_maker_name
    FROM 
        mo
    LEFT JOIN 
        aux_users AS au 
            ON au.id_monday = mo.last_id_consultant
            AND au.row=1
),
regions AS (
   WITH aux AS (SELECT 
        COALESCE(g.sk_offer,ohc.id_offer) AS sk_offer,
        COALESCE(g.sk_house,ohc.id_house_5a) AS sk_house,
        COALESCE(fl_girofer.sk_region,fl_ohc.sk_region) AS sk_region,
        COALESCE(fl_girofer.sk_owner,fl_ohc.sk_owner) AS sk_owner
    FROM 
        giroffer AS g
    FULL OUTER JOIN
        datalake_gsheets_clean_prod.offers_hub_central AS ohc 
            ON ohc.id_offer = g.sk_offer
    LEFT JOIN  
        (SELECT distinct 
            sk_house,
            sk_region,
            sk_owner 
        FROM 
            sale.fact_listings) AS fl_ohc
            ON fl_ohc.sk_house = ohc.id_house_5a
    LEFT JOIN 
        (SELECT distinct
             sk_house,
             sk_region,
             sk_owner 
        FROM 
            sale.fact_listings) AS fl_girofer
            ON fl_girofer.sk_house = g.sk_house
    GROUP BY 1,2,3,4
    )
    SELECT 
        aux.*,
        dr.city_group
    FROM 
        aux
    LEFT JOIN 
        dim_region AS dr 
            ON dr.sk_region = aux.sk_region
),
data_sources AS (
    SELECT
        g.sk_offer,
        g.sk_buyer,
        g.sk_house,
        g.sk_owner,
        g.ts_offer_created,
        g.last_price_offered_by_buyer,
        COALESCE(rbo.sk_user_agent,-1) AS sk_user_agent,
        COALESCE(wc.sk_agent,-1) AS sk_agent,
        rbo.agent_name,
        ohc.id_offer AS ohc_sk_offer,
        ohc.id_user_5a AS ohc_sk_buyer,
        ohc.id_house_5a AS ohc_sk_house,
        ohc.status AS ohc_status,
        wc.contract_name AS agent_work_contract,
        CASE 
            WHEN wc.contract_name LIKE '%HUB%' THEN 'HUB'
            WHEN wc.contract_name LIKE '%CENTRAL%' THEN 'CENTRAL'
            ELSE 'DEAL_MAKING'
        END AS wc_offer_flow,
        CASE 
            WHEN UPPER(wc.contract_name) LIKE '%POA%' THEN 'HUB PORTO ALEGRE'
            WHEN UPPER(wc.contract_name) LIKE '%HAMBURGO%' THEN 'HUB PORTO ALEGRE'
            WHEN UPPER(wc.contract_name) LIKE '%LEOPOLDO%' THEN 'HUB PORTO ALEGRE'
            WHEN UPPER(wc.contract_name) LIKE '%MORUMBI%' THEN 'HUB BUTANTÃ'
            WHEN UPPER(wc.contract_name) LIKE '%BROOKLYN%' THEN 'HUB BROOKLIN'
            ELSE UPPER(wc.contract_name)
        END AS contract_name_ajs,
        CASE 
            WHEN contract_name_ajs LIKE '%HUB%' THEN REPLACE(REPLACE(contract_name_ajs,'-',''),'  ',' ')
        END AS wc_hub_name_ajs,
        CASE 
            WHEN ohc.offer_flow LIKE '%HUB%' THEN 'HUB'
            WHEN ohc.offer_flow LIKE '%CENTRAL%' THEN 'CENTRAL' 
        END AS ohc_offer_flow,
        CASE 
            WHEN ohc.executive_lead = 'Leonardo Monteiro' OR ohc.offer_flow = 'HUB_BV_V0' THEN 'HUB BELA VISTA'
            WHEN ohc.executive_lead LIKE '%Muller%' OR ohc.executive_lead LIKE '%Muller%' THEN 'HUB VILA MADALENA'
            WHEN LOWER(executive_lead) LIKE '%karina%' THEN 'HUB PERDIZES'
            WHEN ohc.executive_lead = 'Rodrigo Pereira' OR ohc.offer_flow = 'HUB_VM_V0' THEN 'HUB VILA MARIANA' 
            WHEN UPPER(ohc.offer_flow) LIKE '%BROOKLYN%' THEN 'HUB BROOKLIN'
            ELSE ohc.offer_flow END AS ohc_offer_flow_detail,
        CASE
            WHEN vft.flow_type LIKE '%HUB%' THEN 'HUB'
            WHEN vft.flow_type LIKE '%CENTRAL%' THEN 'CENTRAL'
            WHEN vft.flow_type = 'DEFAULT' THEN 'DEAL_MAKING' 
        END AS vendas_offer_flow,
        CASE 
            WHEN vs.is_offer_portfolio THEN 'PORTFOLIO_NEGOCIACAO'
            WHEN ohc.id_offer IS NOT NULL THEN 
                (CASE 
                    WHEN ohc.offer_model IS NOT NULL THEN UPPER(ohc.offer_model)
                    ELSE 'GSHEETS'
                 END)
            WHEN vo.sk_offer IS NOT NULL THEN 'VENDAS'
            WHEN mo.sk_offer IS NOT NULL THEN 'MONDAY'
            WHEN g.sk_offer IS NOT NULL THEN 'GIROFFER'
            ELSE 'NOT DEFINED' 
        END AS offer_platform,
        ohc.executive AS ohc_deal_maker_name,
        ohc.executive_lead AS ohc_team_lead_name,
        ohc.sale_price_agreed AS ohc_sale_price_agreed,
        to_char(ts_offer_created,'yyyymmdd')::INT AS g_sk_offer_submitted_date,
        to_char(ohc.dt_offer_submitted,'yyyymmdd')::INT ohc_sk_offer_submitted_date,
        to_char(ohc.dt_offer_accepted,'yyyymmdd')::INT ohc_sk_offer_accepted_date,
        to_char(ohc.dt_offer_dismissed,'yyyymmdd')::INT ohc_sk_offer_dismissed_date,
        to_char(ohc.dt_sale_agreement_signed,'yyyymmdd')::INT ohc_sk_sale_agreement_signed_date,
        to_char(vo.ts_accepted,'yyyymmdd')::INT vo_sk_offer_accepted_date,
        to_char(vo.ts_discarded,'yyyymmdd')::INT AS vo_sk_offer_dismissed_date,
        to_char(vccv.ts_signed,'yyyymmdd')::INT AS vccv_sk_sale_agreement_signed_date,
        to_char(offer_portfolio_start_date,'yyyymmdd')::INT AS sk_offer_portfolio_start_date,
        to_char(mo.dt_offer_accepted,'yyyymmdd')::INT mo_sk_offer_accepted_date,
        to_char(mo.dt_offer_dismissed,'yyyymmdd')::INT AS mo_sk_offer_dismissed_date,
        to_char(mo.dt_sale_agreement_signed,'yyyymmdd')::INT AS mo_sk_sale_agreement_signed_date,
        is_offer_portfolio,
        vo.status AS vendas_offer_status,
        vo.id_sales_flow AS sk_sales_flow,
        vs.deal_maker_name AS vo_deal_maker_name,
        vs.team_lead_name AS vo_team_lead_name,
        CASE 
            WHEN vs.sk_deal_maker IS NOT NULL THEN 'ID_vendas_' || vs.sk_deal_maker 
        END AS vo_sk_deal_maker,
        CASE 
            WHEN vs.sk_team_lead IS NOT NULL THEN 'ID_vendas_' || vs.sk_team_lead 
        END AS vo_sk_team_lead,
        CASE 
            WHEN mo.sk_deal_maker IS NOT NULL THEN 'ID_MONDAY_' || mo.sk_deal_maker 
        END AS mo_sk_deal_maker,
        mo.status AS monday_offer_status,
        mo.deal_maker_name AS mo_deal_maker_name,
        mo.sale_price_agreed AS mo_sale_price_agreed
    FROM 
        giroffer AS g
    LEFT JOIN 
        relation_booking_offer AS rbo
            ON rbo.sk_offer = g.sk_offer
    full outer JOIN 
        datalake_gsheets_clean_prod.offers_hub_central AS ohc
            ON ohc.id_offer = g.sk_offer
    LEFT JOIN 
        vendas_flow_type AS vft
            ON vft.sk_offer = g.sk_offer
    LEFT JOIN 
        vendas_offers AS vo 
            ON vo.sk_offer = g.sk_offer
    LEFT JOIN 
        monday_offers AS mo 
            ON mo.sk_offer = g.sk_offer
    LEFT JOIN 
        vendas_ccvs AS vccv
            ON vccv.sk_offer = g.sk_offer
    LEFT JOIN 
        work_contract AS wc
            ON wc.sk_user_agent = rbo.sk_user_agent 
            AND g.ts_offer_created >= wc.ts_work_contract_start
            AND ((g.ts_offer_created <= wc.ts_work_contract_end) OR (wc.ts_work_contract_end is null))
    LEFT JOIN
        vendas_specialists AS vs
            ON vs.sk_offer = g.sk_offer
),
business_rules AS (
    SELECT 
        COALESCE(ds.sk_offer,ds.ohc_sk_offer) AS sk_offer,
        COALESCE(ds.sk_sales_flow,-1) AS sk_sales_flow,
        COALESCE(ds.sk_buyer,ds.ohc_sk_buyer,-1) AS sk_buyer,
        COALESCE(ds.sk_house,ds.ohc_sk_house,-1) AS sk_house,
        COALESCE(dr.sk_owner,-1) AS sk_owner,
        COALESCE(dr.sk_region,-1) AS sk_region,
        COALESCE(ds.sk_user_agent,-1) AS sk_user_agent,
        COALESCE(ds.sk_agent,-1) AS sk_agent,
        CASE 
            WHEN ds.ohc_offer_flow IS NOT NULL THEN ds.ohc_offer_flow -- Offers que estão na planilha de trabalho
            WHEN ds.is_offer_portfolio = true THEN 'HUB' -- Offers que estão no portfólio de negociação
            WHEN mo_sk_deal_maker IS NOT NULL THEN 'DEAL_MAKING' -- Offers que tem deal maker Associado
            WHEN ds.vendas_offer_flow = 'DEAL_MAKING' THEN 'DEAL_MAKING' -- Offers que não estão na planilha de trabalho e o Vendas diz ser DM
            WHEN ds.offer_platform = 'MONDAY' THEN 'DEAL_MAKING' -- Offers que não estão na planiha de trabalho e estão apenas no monday
            ELSE 'NOT DEFINED' -- Offers que não estão na planilha de trabalho, não foram atribuidAS a um deal maker e possuem offer_flows diferentes de DM no Vendas.
        END AS offer_flow,
        REPLACE(UPPER(
            CASE 
                WHEN offer_flow = 'CENTRAL' AND dr.city_group = 'Porto Alegre' THEN 'CENTRAL POA'
                WHEN offer_flow = 'CENTRAL' AND dr.city_group = 'RMSP' THEN 'CENTRAL SP'
                WHEN offer_flow = 'CENTRAL' AND dr.city_group = 'Rio de Janeiro' THEN 'CENTRAL RJ'
                WHEN offer_flow = 'CENTRAL' THEN 'CENTRAL NO INFO'
                WHEN offer_flow = 'HUB' THEN (CASE WHEN ds.ohc_offer_flow_detail is null AND offer_platform = 'PORTFOLIO_NEGOCIACAO' THEN wc_hub_name_ajs ELSE ds.ohc_offer_flow_detail END)
                ELSE offer_flow 
            END
        ), '  ',' ') AS business_unit,
        ohc_offer_flow_detail,
        COALESCE(ds.g_sk_offer_submitted_date, ds.ohc_sk_offer_submitted_date,-1) AS sk_offer_submitted_date,
        CASE 
            WHEN offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE 
                        WHEN ds.is_offer_portfolio AND sk_offer_submitted_date >= sk_offer_portfolio_start_date THEN COALESCE(ds.vo_sk_offer_accepted_date,ds.ohc_sk_offer_accepted_date,-1) 
                        ELSE COALESCE(ds.ohc_sk_offer_accepted_date,ds.vo_sk_offer_accepted_date,-1) 
                    END) 
            ELSE COALESCE(ds.mo_sk_offer_accepted_date,ds.vo_sk_offer_accepted_date,-1) 
        END  AS sk_offer_accepted_date,
        CASE 
            WHEN offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN ds.is_offer_portfolio AND sk_offer_submitted_date >= sk_offer_portfolio_start_date THEN COALESCE(ds.vo_sk_offer_dismissed_date,ds.ohc_sk_offer_dismissed_date,-1) 
                        ELSE COALESCE(ds.ohc_sk_offer_dismissed_date,ds.vo_sk_offer_dismissed_date,-1) 
                    END) 
            ELSE COALESCE(ds.mo_sk_offer_dismissed_date,ds.vo_sk_offer_dismissed_date,-1) 
        END  AS sk_offer_dismissed_date,
        CASE
            WHEN offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN ds.is_offer_portfolio AND sk_offer_submitted_date >= sk_offer_portfolio_start_date THEN COALESCE(ds.vccv_sk_sale_agreement_signed_date,ds.ohc_sk_sale_agreement_signed_date,-1) 
                        ELSE COALESCE(ds.ohc_sk_sale_agreement_signed_date,ds.vccv_sk_sale_agreement_signed_date,-1)
                    END) 
            ELSE COALESCE(ds.mo_sk_sale_agreement_signed_date,ds.vccv_sk_sale_agreement_signed_date,-1) 
        END  AS sk_sale_agreement_signed_date, 
        UPPER(
            CASE 
                WHEN offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE 
                        WHEN ds.is_offer_portfolio AND sk_offer_submitted_date >= sk_offer_portfolio_start_date THEN ds.vendas_offer_status 
                    ELSE COALESCE(ds.ohc_status,ds.vendas_offer_status) 
                END) 
                ELSE COALESCE(ds.monday_offer_status,ds.vendas_offer_status) 
            END
        ) AS offer_status, 
        UPPER(ds.agent_name) AS agent_name,
        UPPER(ds.agent_work_contract) AS agent_work_contract,
        ds.offer_platform,
        ds.vo_sk_team_lead AS id_team_lead,
        UPPER(
            CASE 
                WHEN offer_flow IN ('HUB','CENTRAL') THEN (
                        CASE
                            WHEN ds.is_offer_portfolio AND sk_offer_submitted_date >= sk_offer_portfolio_start_date THEN ds.vo_team_lead_name 
                            ELSE COALESCE(ds.ohc_team_lead_name,ds.vo_team_lead_name) 
                        END) 
                ELSE ds.vo_team_lead_name 
            END)  AS team_lead_name, 
        UPPER(
            CASE 
                WHEN ds.ohc_sk_offer IS NOT NULL THEN 'GSHEETS_[]' 
                ELSE COALESCE(ds.vo_sk_deal_maker,ds.mo_sk_deal_maker) 
            END
        ) AS id_deal_maker,
        UPPER(
            CASE 
                WHEN offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE 
                        WHEN ds.is_offer_portfolio AND sk_offer_submitted_date >= sk_offer_portfolio_start_date THEN ds.vo_deal_maker_name 
                        ELSE COALESCE(ds.ohc_deal_maker_name,ds.vo_deal_maker_name) 
                    END) 
                ELSE COALESCE(ds.mo_deal_maker_name,ds.vo_deal_maker_name) 
            END
        )  AS deal_maker_name, 
        CASE 
            WHEN offer_flow IN ('HUB','CENTRAL') THEN (
                    CASE
                        WHEN ds.is_offer_portfolio AND sk_offer_submitted_date >= sk_offer_portfolio_start_date THEN ds.last_price_offered_by_buyer 
                        ELSE (CASE
                                WHEN UPPER(ds.ohc_status) IN ('CONTRATO ASSINADO','DESCARTADO') THEN ds.ohc_sale_price_agreed 
                                ELSE COALESCE(ds.last_price_offered_by_buyer,ds.ohc_sale_price_agreed) 
                              END)
                    END) 
            ELSE COALESCE(ds.last_price_offered_by_buyer,ds.mo_sale_price_agreed) 
        END AS last_price_offered_by_buyer
    FROM 
        data_sources AS ds
    LEFT JOIN 
        regions AS dr
            ON dr.sk_offer = COALESCE(ds.sk_offer,ds.ohc_sk_offer)
)
SELECT 
    sk_offer,
    sk_sales_flow,
    sk_buyer,
    sk_house,
    sk_owner,
    sk_region,
    sk_user_agent,
    sk_agent,
    sk_offer_submitted_date,
    sk_offer_accepted_date,
    sk_offer_dismissed_date,
    sk_sale_agreement_signed_date,
    id_team_lead,
    id_deal_maker,
    team_lead_name,
    deal_maker_name,
    offer_flow,
    business_unit,
    offer_platform,
    offer_status,
    agent_name,
    agent_work_contract,
    last_price_offered_by_buyer,
    GETDATE() AS ts_load
FROM 
    business_rules