-- =============================================================================
--   1. MÉTRICA BASE: prospects (cd_funnel_step = 'prospect') para rateio rent/sale e leads para rateio CRO.
--
--   2. GRANULARIDADE TEMPORAL: fator de rateio usa o mês anterior (mês-1).
--
--   3. CHAVE DE RATEIO: join por dimensões de campanha
--      (city_group, campaign_landing_page, campaign_business_context, source, medium)
--      em vez de (nm_campaign, naming_convention_sufix).
--
--   4. REGRA RENT/SALE EXPLÍCITA:
--       - campaign_business_context = 'Rent'   → 100% Rent
--       - campaign_business_context = 'Sale'   → 100% Sale
--       - campaign_business_context = 'Hybrid' → proporcional a prospects RENT/SALE
--
--   5. CÁLCULO EM DOIS PASSOS (fix de dupla contagem):
--      O share Rent/Sale é calculado com COUNT DISTINCT por nm_business_context,
--      sem planning_cluster/company_report_origin no denominador — evita inflação
--      do total quando o mesmo supply aparece em múltiplos planning_clusters.
--      A distribuição interna por (company_report_origin, planning_cluster) é
--      feita DENTRO de cada business context, separadamente.
--
-- FALLBACK (sem dados de prospects no mês anterior):
--   Rent puro → 1 linha Rent, shared_cost = costs
--   Sale puro → 1 linha Sale, shared_cost = costs
--   Hybrid    → 2 linhas, 50% Rent / 50% Sale, company_report_origin e
--               planning_cluster = NULL
-- =============================================================================
-- PASSO A PASSO:
-- 1. Custo total da campanha
-- 2. Share de leads por CRO (Leads CRO / Leads Totais da Campanha)
-- 3. Custo por CRO (Cálculo implícito na multiplicação)
-- 4. Share de prospects por BU (Prospects Rent/Sale / Prospects Totais do CRO)
-- 5. Custo Final por BU (Multiplicação de todas as frações)
-- =============================================================================
WITH
-- -----------------------------------------------------------------------------
-- PASSO 2: Share de leads por Company Report Origin
-- Volume de leads por origem ÷ total de leads da campanha
-- -----------------------------------------------------------------------------
leads_share AS (
    SELECT
        DATE_TRUNC('month', obt.date) AS year_month,
        obt.city_group,
        obt.campaign_landing_page,
        obt.campaign_business_context,
        obt.source,
        obt.medium,
        obt.company_report_origin,
        obt.planning_cluster,
        COUNT(DISTINCT obt.sk_supply) AS leads_cro,
        SUM(COUNT(DISTINCT obt.sk_supply)) OVER (
            PARTITION BY
                DATE_TRUNC('month', obt.date),
                obt.city_group,
                obt.campaign_landing_page,
                obt.campaign_business_context,
                obt.source,
                obt.medium
        ) AS leads_total_campaign
    FROM
        dw_growth.obt_supply AS obt
    WHERE
        obt.cd_funnel_step = 'lead'
        AND obt.campaign_landing_page IS NOT NULL
        AND obt.campaign_business_context IS NOT NULL
        AND obt.source IS NOT NULL
        AND obt.medium IS NOT NULL
        AND obt.date >= DATE '2025-01-01'
        AND company_report_origin IN (
            'Price Calculator',
            'Price Calculator - Sale',
            'Owner PWA - Paid',
            'Inbound'
        )
    GROUP BY ALL
),
-- -----------------------------------------------------------------------------
-- PASSO 4: Share de prospects por BU dentro da origem
-- Prospects Rent e Sale ÷ total de prospects da origem (CRO)
-- -----------------------------------------------------------------------------
prospects_share AS (
    SELECT
        DATE_TRUNC('month', obt.date) AS year_month,
        obt.city_group,
        obt.campaign_landing_page,
        obt.campaign_business_context,
        obt.source,
        obt.medium,
        obt.company_report_origin,
        obt.planning_cluster,
        obt.nm_business_context, -- BU (Rent ou Sale)
        COUNT(DISTINCT obt.sk_supply) AS prospects_bu,
        SUM(COUNT(DISTINCT obt.sk_supply)) OVER (
            PARTITION BY
                DATE_TRUNC('month', obt.date),
                obt.city_group,
                obt.campaign_landing_page,
                obt.campaign_business_context,
                obt.source,
                obt.medium,
                obt.company_report_origin,
                obt.planning_cluster
        ) AS prospects_total_cro
    FROM
        dw_growth.obt_supply AS obt
    WHERE
        obt.cd_funnel_step = 'prospect'
        AND obt.campaign_landing_page IS NOT NULL
        AND obt.campaign_business_context IS NOT NULL
        AND obt.source IS NOT NULL
        AND obt.medium IS NOT NULL
        AND obt.date >= DATE '2025-01-01'
        AND obt.company_report_origin IN (
            'Price Calculator',
            'Price Calculator - Sale',
            'Owner PWA - Paid',
            'Inbound'
        )
    GROUP BY ALL
),
-- -----------------------------------------------------------------------------
-- PASSO 1: Custo total da campanha
-- (Mantido igual aos seus modelos base)
-- -----------------------------------------------------------------------------
costs AS (
    SELECT
        dd.date,
        dr.city_group,
        mc.utm_campaign AS nm_campaign,
        mc.sk_campaign AS id_campaign,
        ms.naming_convention_sufix,
        ms.campaign_strategy_intent,
        ms.campaign_landing_page,
        ms.campaign_business_context,
        ms.source,
        ms.medium,
        ms.funnel_side,
        ms.behavior_type,
        SUM(total_cost * COALESCE(share, 1)) AS costs
    FROM
        dw_growth.fact_media_platform_metrics AS mc
    JOIN
        dw_public.dim_date AS dd
            ON dd.sk_date = mc.sk_cost_date
    LEFT JOIN
        dw_growth.dim_media_setup AS ms
            ON ms.naming_convention_sufix = mc.naming_convention_sufix
    LEFT JOIN
        dw_public.dim_region AS dr
            ON dr.sk_region = mc.sk_region
    LEFT JOIN
        dw_growth.dim_sharing_rules AS sr
            ON sr.bk_sharing_rules = mc.bk_sharing_rules
            AND utm_campaign_modified = SUBSTRING(
                mc.utm_campaign,
                POSITION('.' IN mc.utm_campaign) + 1
            )
    WHERE
        ms.funnel_side = 'Supply'
    GROUP BY ALL
),
-- -----------------------------------------------------------------------------
-- VERIFICAÇÃO DE DADOS (FALLBACK)
-- Garante que só passa pelo caminho principal se houver dados de leads E prospects
-- -----------------------------------------------------------------------------
covered_cost_keys AS (
    SELECT DISTINCT
        DATE_ADD(month, -1, DATE_TRUNC('month', c.date)) AS ref_year_month,
        LOWER(c.city_group) AS city_group_lc,
        LOWER(c.campaign_landing_page) AS campaign_landing_page_lc,
        LOWER(c.campaign_business_context) AS campaign_business_context_lc,
        LOWER(c.source) AS source_lc,
        LOWER(c.medium) AS medium_lc
    FROM
        costs AS c
    INNER JOIN
        leads_share AS ls
            ON DATE_ADD(month, -1, DATE_TRUNC('month', c.date)) = ls.year_month
            AND LOWER(c.city_group) = LOWER(ls.city_group)
            AND LOWER(c.campaign_landing_page) = LOWER(ls.campaign_landing_page)
            AND LOWER(c.campaign_business_context) = LOWER(ls.campaign_business_context)
            AND LOWER(c.source) = LOWER(ls.source)
            AND LOWER(c.medium) = LOWER(ls.medium)
    INNER JOIN
        prospects_share AS ps
            ON ls.year_month = ps.year_month
            AND LOWER(ls.city_group) = LOWER(ps.city_group)
            AND LOWER(ls.campaign_landing_page) = LOWER(ps.campaign_landing_page)
            AND LOWER(ls.source) = LOWER(ps.source)
            AND LOWER(ls.medium) = LOWER(ps.medium)
            AND ls.company_report_origin = ps.company_report_origin
            AND ls.planning_cluster = ps.planning_cluster
)
-- =============================================================================
-- CAMINHO PRINCIPAL: APLICAÇÃO DA FÓRMULA FINAL DA IMAGEM
-- =============================================================================
SELECT
    c.date,
    c.city_group,
    c.naming_convention_sufix,
    c.nm_campaign,
    c.id_campaign,
    c.campaign_strategy_intent,
    c.campaign_landing_page,
    c.campaign_business_context,
    CASE
        WHEN ps.nm_business_context = 'RENT' THEN 'Rent'
        WHEN ps.nm_business_context = 'SALE' THEN 'Sale'
        ELSE ps.nm_business_context
    END AS nm_business_context_mkt,
    ls.company_report_origin,
    ls.planning_cluster,
    c.source,
    c.medium,
    c.funnel_side,
    c.behavior_type,
    -- ====================================================================
    -- PASSO 5: FÓRMULA COMPLETA
    -- Custo Total * Share_Leads(origem) * Share_Prospects(BU|origem)
    -- ====================================================================
    c.costs
        * (
            CAST(ls.leads_cro AS DOUBLE)
            / NULLIF(CAST(ls.leads_total_campaign AS DOUBLE), 0)
        )
        * (
            CAST(ps.prospects_bu AS DOUBLE)
            / NULLIF(CAST(ps.prospects_total_cro AS DOUBLE), 0)
        ) AS shared_cost
FROM
    costs AS c
INNER JOIN
    covered_cost_keys AS cck
        ON DATE_ADD(month, -1, DATE_TRUNC('month', c.date)) = cck.ref_year_month
        AND LOWER(c.city_group) = cck.city_group_lc
        AND LOWER(c.campaign_landing_page) = cck.campaign_landing_page_lc
        AND LOWER(c.campaign_business_context) = cck.campaign_business_context_lc
        AND LOWER(c.source) = cck.source_lc
        AND LOWER(c.medium) = cck.medium_lc
INNER JOIN
    leads_share AS ls
        ON DATE_ADD(month, -1, DATE_TRUNC('month', c.date)) = ls.year_month
        AND LOWER(c.city_group) = LOWER(ls.city_group)
        AND LOWER(c.campaign_landing_page) = LOWER(ls.campaign_landing_page)
        AND LOWER(c.campaign_business_context) = LOWER(ls.campaign_business_context)
        AND LOWER(c.source) = LOWER(ls.source)
        AND LOWER(c.medium) = LOWER(ls.medium)
INNER JOIN
    prospects_share AS ps
        ON ls.year_month = ps.year_month
        AND LOWER(ls.city_group) = LOWER(ps.city_group)
        AND LOWER(ls.campaign_landing_page) = LOWER(ps.campaign_landing_page)
        AND LOWER(ls.campaign_business_context) = LOWER(ps.campaign_business_context)
        AND LOWER(ls.source) = LOWER(ps.source)
        AND LOWER(ls.medium) = LOWER(ps.medium)
        AND ls.company_report_origin = ps.company_report_origin
        AND ls.planning_cluster = ps.planning_cluster
UNION ALL
-- =============================================================================
-- FALLBACK RENT (Mesma lógica de proteção)
-- =============================================================================
SELECT
    c.date,
    c.city_group,
    c.naming_convention_sufix,
    c.nm_campaign,
    c.id_campaign,
    c.campaign_strategy_intent,
    c.campaign_landing_page,
    c.campaign_business_context,
    'Rent' AS nm_business_context_mkt,
    NULL AS company_report_origin,
    NULL AS planning_cluster,
    c.source,
    c.medium,
    c.funnel_side,
    c.behavior_type,
    CASE
        WHEN LOWER(c.campaign_business_context) = 'rent' THEN c.costs
        ELSE c.costs * 0.5
    END AS shared_cost
FROM
    costs AS c
LEFT JOIN
    covered_cost_keys AS cck
        ON DATE_ADD(month, -1, DATE_TRUNC('month', c.date)) = cck.ref_year_month
        AND LOWER(c.city_group) = cck.city_group_lc
        AND LOWER(c.campaign_landing_page) = cck.campaign_landing_page_lc
        AND LOWER(c.campaign_business_context) = cck.campaign_business_context_lc
        AND LOWER(c.source) = cck.source_lc
        AND LOWER(c.medium) = cck.medium_lc
WHERE
    cck.ref_year_month IS NULL
    AND LOWER(c.campaign_business_context) IN ('rent', 'hybrid')
UNION ALL
-- =============================================================================
-- FALLBACK SALE (Mesma lógica de proteção)
-- =============================================================================
SELECT
    c.date,
    c.city_group,
    c.naming_convention_sufix,
    c.nm_campaign,
    c.id_campaign,
    c.campaign_strategy_intent,
    c.campaign_landing_page,
    c.campaign_business_context,
    'Sale' AS nm_business_context_mkt,
    NULL AS company_report_origin,
    NULL AS planning_cluster,
    c.source,
    c.medium,
    c.funnel_side,
    c.behavior_type,
    CASE
        WHEN LOWER(c.campaign_business_context) = 'sale' THEN c.costs
        ELSE c.costs * 0.5
    END AS shared_cost
FROM
    costs AS c
LEFT JOIN
    covered_cost_keys AS cck
        ON DATE_ADD(month, -1, DATE_TRUNC('month', c.date)) = cck.ref_year_month
        AND LOWER(c.city_group) = cck.city_group_lc
        AND LOWER(c.campaign_landing_page) = cck.campaign_landing_page_lc
        AND LOWER(c.campaign_business_context) = cck.campaign_business_context_lc
        AND LOWER(c.source) = cck.source_lc
        AND LOWER(c.medium) = cck.medium_lc
WHERE
    cck.ref_year_month IS NULL
    AND LOWER(c.campaign_business_context) IN ('sale', 'hybrid')
