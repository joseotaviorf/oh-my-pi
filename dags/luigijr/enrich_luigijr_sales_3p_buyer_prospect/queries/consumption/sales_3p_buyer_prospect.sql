with base_eventos_completa AS (
        -- 1. Captura histórico total usando a tag do HubSpot e mapeamento de canal
        SELECT 
            b.id_visitor,
            b.sk_booking,
            b.id_visit,
            b.id_agent,
            case when bm_sub.sk_broker_demand = 650 and dr.city_group = 'Campinas' then 58049 else bm_sub.sk_broker_demand end sk_broker_demand,
            date(b.dt_created) as data_evento,
            fact.sk_offer,
            fact.ts_sale_agreement_signed,
            CASE 
                WHEN bm_sub.business_model IN ('BM_3P_DEMAND_1P_SUPPLY','BM_3P_DEMAND_3P_SUPPLY_6P','BM_3P_DEMAND_3P_SUPPLY') THEN 'TQC 3P'
                WHEN bm_sub.business_model IN ('BM_3P_LEAD_GEN_3P_SUPPLY','BM_3P_LEAD_GEN_1P_SUPPLY','BM_3P_LEAD_GEN_3P_SUPPLY_6P') THEN 'CQA'
                WHEN bm_sub.business_model IN ('BM_1P', 'BM_3P_SUPPLY_1P_DEMAND_AGENT') 
                    OR bm_sub.business_model IS NULL THEN '1P'
                ELSE '1P' 
            END as canal_grupo
        FROM dw_public.dim_booking b
        INNER JOIN datalake_visit.visit_business_model bm_sub ON bm_sub.id_visit = b.id_visit
        LEFT JOIN dw_sale.fact_offers fact ON b.sk_booking = fact.sk_booking 
        inner join dw_sale.fact_sale_demand_event de on b.sk_booking = de.sk_booking
        left join dw_public.dim_region as dr ON dr.sk_region = de.sk_region
        WHERE b.visit_intent = 'SALE'
        group by all

    )
    , calculo_predecessor AS (
        -- 2. Janela Mista: LAG Global (para Avulsas) e Janela Local (para Ciclos na Imobiliária)
        SELECT 
            bc.id_visitor,
            bc.sk_booking,
            bc.id_visit,
            bc.id_agent,
            bc.sk_broker_demand,
            bc.data_evento,
            bc.sk_offer,
            bc.ts_sale_agreement_signed,
            bc.canal_grupo,

            LAG(data_evento) OVER (PARTITION BY id_visitor ORDER BY data_evento ASC, sk_booking ASC) as data_evento_anterior_global,
            LAG(canal_grupo) OVER (PARTITION BY id_visitor ORDER BY data_evento ASC, sk_booking ASC) as canal_anterior_global,
            LAG(data_evento) OVER (PARTITION BY id_visitor, bc.sk_broker_demand ORDER BY data_evento ASC, sk_booking ASC) as data_evento_anterior_local,
            MIN(data_evento) OVER (PARTITION BY id_visitor, bc.sk_broker_demand) as data_primeira_visita_imobiliaria
        FROM base_eventos_completa bc

    ),

    identificacao_ciclos AS (
        -- 3. Define ciclos de 90 dias específicos para a imobiliária
        SELECT 
            *,
            SUM(CASE 
                    WHEN data_evento_anterior_local IS NULL OR datediff(data_evento, data_evento_anterior_local) > 90 THEN 1 
                    ELSE 0 
                END) OVER (PARTITION BY id_visitor, sk_broker_demand ORDER BY data_evento ASC, sk_booking ASC) as id_ciclo
        FROM calculo_predecessor
    ),

    status_por_evento AS (
        -- 4. Classificação: Prioriza 'Visita Avulsa' se houver histórico 1P Global
        SELECT 
            *,
            CASE 
                WHEN canal_grupo = '1P' THEN 'OUTRO'
                WHEN data_evento = data_primeira_visita_imobiliaria 
                    AND canal_anterior_global = '1P' 
                    AND datediff(data_evento, data_evento_anterior_global) <= 90 THEN 'Visita Avulsa'
                WHEN data_evento = data_primeira_visita_imobiliaria THEN 'nBP'
                WHEN datediff(data_evento, data_evento_anterior_local) > 90 THEN 'rBP'
                ELSE 'nBP'
            END as status_temporario
        FROM identificacao_ciclos
    ),

    fidelizacao_no_target AS (
        -- 5. FIDELIZAÇÃO: Trava por Visitante, Imobiliária e Ciclo
        -- canal_grupo_fiel garante que visitas no mesmo dia em canais distintos
        -- não dupliquem o BP: apenas o canal da primeira visita (menor sk_booking) conta
        SELECT 
            *,
            FIRST_VALUE(data_evento)       OVER (PARTITION BY id_visitor, sk_broker_demand, id_ciclo ORDER BY data_evento ASC, sk_booking ASC) as data_cohort_fiel,
            FIRST_VALUE(status_temporario) OVER (PARTITION BY id_visitor, sk_broker_demand, id_ciclo ORDER BY data_evento ASC, sk_booking ASC) as segmentation_fiel,
            FIRST_VALUE(canal_grupo)       OVER (PARTITION BY id_visitor, sk_broker_demand, id_ciclo ORDER BY data_evento ASC, sk_booking ASC) as canal_grupo_fiel
        FROM status_por_evento
        WHERE canal_grupo IN ('TQC 3P', 'CQA')
    )
    select 
        sk_broker_demand as sk_broker
        ,id_visitor
        ,id_agent
        ,sk_offer
        ,date(ts_sale_agreement_signed) as ts_sale_agreement_signed
        ,case when canal_grupo_fiel = 'TQC 3P' then 'demand' else 'lead_gen' end  as business_model
        ,date(data_cohort_fiel) as data_cohort
        ,segmentation_fiel
    from fidelizacao_no_target
    group by all
