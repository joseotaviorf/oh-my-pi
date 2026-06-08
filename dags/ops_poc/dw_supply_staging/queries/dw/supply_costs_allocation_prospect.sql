-- =============================================================================
--   1. MÉTRICA BASE: prospects (cd_funnel_step = 'prospect') no lugar de leads.
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

WITH

-- -----------------------------------------------------------------------------
-- rent_sale_shares: share Rent/Sale por combinação de dimensões de campanha.
-- Usa COUNT DISTINCT por nm_business_context SEM planning_cluster ou
-- company_report_origin no denominador — evita dupla contagem de supplies
-- que aparecem em múltiplos planning_clusters no mesmo mês.
-- Referência: mês-1 em relação ao mês do custo.
-- -----------------------------------------------------------------------------
rent_sale_shares AS (
  SELECT
    DATE_TRUNC('month', obt.date)  AS year_month,
    obt.city_group,
    obt.campaign_landing_page,
    obt.campaign_business_context,
    obt.source,
    obt.medium,
    COUNT(DISTINCT CASE WHEN obt.nm_business_context = 'RENT' THEN obt.sk_supply END) AS prospects_rent,
    COUNT(DISTINCT CASE WHEN obt.nm_business_context = 'SALE' THEN obt.sk_supply END) AS prospects_sale
  FROM dw_growth.obt_supply obt
  WHERE obt.cd_funnel_step = 'prospect'
    AND obt.campaign_landing_page     IS NOT NULL
    AND obt.campaign_business_context IS NOT NULL
    AND obt.source                    IS NOT NULL
    AND obt.medium                    IS NOT NULL
    AND obt.date >= DATE '2025-01-01'
  GROUP BY ALL
),

-- -----------------------------------------------------------------------------
-- prospect_dist: distribuição de (company_report_origin, planning_cluster)
-- DENTRO de cada (nm_business_context × dimensões de campanha).
-- Usado para segmentar o custo já alocado por Rent/Sale em sub-linhas
-- por origem e cluster de planejamento.
-- O denominador (total_by_context) é o total de prospects do mesmo
-- nm_business_context — sem misturar RENT e SALE, evitando distorção.
-- -----------------------------------------------------------------------------
prospect_dist AS (
  SELECT
    DATE_TRUNC('month', obt.date)  AS year_month,
    obt.city_group,
    obt.campaign_landing_page,
    obt.campaign_business_context,
    obt.source,
    obt.medium,
    obt.nm_business_context,
    obt.company_report_origin,
    obt.planning_cluster,
    COUNT(DISTINCT obt.sk_supply)   AS n_prospects,
    SUM(COUNT(DISTINCT obt.sk_supply)) OVER (
      PARTITION BY
        DATE_TRUNC('month', obt.date),
        obt.city_group,
        obt.campaign_landing_page,
        obt.campaign_business_context,
        obt.source,
        obt.medium,
        obt.nm_business_context       -- denominador separado por business context
    )                               AS total_by_context
  FROM dw_growth.obt_supply obt
  WHERE obt.cd_funnel_step = 'prospect'
    AND obt.campaign_landing_page     IS NOT NULL
    AND obt.campaign_business_context IS NOT NULL
    AND obt.source                    IS NOT NULL
    AND obt.medium                    IS NOT NULL
    AND obt.date >= DATE '2025-01-01'
  GROUP BY ALL
),

-- -----------------------------------------------------------------------------
-- costs: custos de mídia de Supply, agrupados por dia/campanha/cidade.
-- Idêntico ao modelo anterior.
-- -----------------------------------------------------------------------------
costs AS (
  SELECT
    dd.date,
    dr.city_group,
    mc.utm_campaign              AS nm_campaign,
    mc.sk_campaign               AS id_campaign,
    ms.naming_convention_sufix,
    ms.campaign_strategy_intent,
    ms.campaign_landing_page,
    ms.campaign_business_context,
    ms.source,
    ms.medium,
    ms.funnel_side,
    ms.behavior_type,
    SUM(total_cost * COALESCE(share, 1)) AS costs
  FROM dw_growth.fact_media_platform_metrics mc
  JOIN dw_public.dim_date dd
    ON dd.sk_date = mc.sk_cost_date
  LEFT JOIN dw_growth.dim_media_setup ms
    ON ms.naming_convention_sufix = mc.naming_convention_sufix
  LEFT JOIN dw_public.dim_region dr
    ON dr.sk_region = mc.sk_region
  LEFT JOIN dw_growth.dim_sharing_rules sr
    ON  sr.bk_sharing_rules    = mc.bk_sharing_rules
    AND utm_campaign_modified   = SUBSTRING(
          mc.utm_campaign,
          POSITION('.' IN mc.utm_campaign) + 1
        )
  WHERE ms.funnel_side = 'Supply'
  GROUP BY ALL
),

-- -----------------------------------------------------------------------------
-- covered_cost_keys: combinações de dimensões de custo com dados de prospects
-- no mês anterior (para separar caminho principal do fallback).
-- -----------------------------------------------------------------------------
covered_cost_keys AS (
  -- Marca como "coberto" apenas quando prospect_dist tem linhas que o caminho
  -- principal de fato vai consumir (mesmo filtro de nm_business_context).
  -- Garante que um custo marcado como coberto nunca seja silenciosamente descartado
  -- por falta de linhas no INNER JOIN com prospect_dist.
  SELECT DISTINCT
    ADD_MONTHS(DATE_TRUNC('month', c.date), -1)  AS ref_year_month,
    LOWER(c.city_group)                           AS city_group_lc,
    LOWER(c.campaign_landing_page)                AS campaign_landing_page_lc,
    LOWER(c.campaign_business_context)            AS campaign_business_context_lc,
    LOWER(c.source)                               AS source_lc,
    LOWER(c.medium)                               AS medium_lc
  FROM costs c
  INNER JOIN prospect_dist pd
    ON  ADD_MONTHS(DATE_TRUNC('month', c.date), -1) = pd.year_month
    AND LOWER(c.city_group)               = LOWER(pd.city_group)
    AND LOWER(c.campaign_landing_page)    = LOWER(pd.campaign_landing_page)
    AND LOWER(c.campaign_business_context)= LOWER(pd.campaign_business_context)
    AND LOWER(c.source)                   = LOWER(pd.source)
    AND LOWER(c.medium)                   = LOWER(pd.medium)
    -- Espelha exatamente o filtro de nm_business_context do caminho principal
    AND (
      (LOWER(c.campaign_business_context) = 'rent'  AND pd.nm_business_context = 'RENT')
      OR (LOWER(c.campaign_business_context) = 'sale' AND pd.nm_business_context = 'SALE')
      OR  LOWER(c.campaign_business_context) = 'hybrid'
    )
)

-- =============================================================================
-- CAMINHO PRINCIPAL: custos com dados de prospects no mês anterior.
--
-- Lógica em dois passos:
--   1. share_rent = prospects_rent / (prospects_rent + prospects_sale)
--      calculado com COUNT DISTINCT correto (rent_sale_shares)
--   2. shared_cost distribuído por (company_report_origin, planning_cluster)
--      proporcionalmente dentro de cada business context (prospect_dist)
--
-- shared_cost final por linha =
--   costs × share_business_context × (n_prospects_combo / total_by_context)
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
    WHEN pd.nm_business_context = 'RENT' THEN 'Rent'
    WHEN pd.nm_business_context = 'SALE' THEN 'Sale'
    ELSE pd.nm_business_context
  END                                                                          AS nm_business_context_mkt,
  pd.company_report_origin,
  pd.planning_cluster,
  c.source,
  c.medium,
  c.funnel_side,
  c.behavior_type,
  -- Passo 1: share do business context (Rent/Sale)
  -- Passo 2: distribuição interna por (company_report_origin, planning_cluster)
  c.costs
    * CASE
        WHEN LOWER(c.campaign_business_context) = 'rent'
          THEN 1.0
        WHEN LOWER(c.campaign_business_context) = 'sale'
          THEN 1.0
        WHEN LOWER(c.campaign_business_context) = 'hybrid'
             AND (rss.prospects_rent + rss.prospects_sale) > 0
             AND pd.nm_business_context = 'RENT'
          THEN CAST(rss.prospects_rent AS DOUBLE)
               / CAST(rss.prospects_rent + rss.prospects_sale AS DOUBLE)
        WHEN LOWER(c.campaign_business_context) = 'hybrid'
             AND (rss.prospects_rent + rss.prospects_sale) > 0
             AND pd.nm_business_context = 'SALE'
          THEN CAST(rss.prospects_sale AS DOUBLE)
               / CAST(rss.prospects_rent + rss.prospects_sale AS DOUBLE)
        ELSE 0.5
      END
    * CAST(pd.n_prospects AS DOUBLE)
      / CAST(pd.total_by_context AS DOUBLE)                                    AS shared_cost
FROM costs c
INNER JOIN covered_cost_keys cck
  ON  ADD_MONTHS(DATE_TRUNC('month', c.date), -1) = cck.ref_year_month
  AND LOWER(c.city_group)               = cck.city_group_lc
  AND LOWER(c.campaign_landing_page)    = cck.campaign_landing_page_lc
  AND LOWER(c.campaign_business_context)= cck.campaign_business_context_lc
  AND LOWER(c.source)                   = cck.source_lc
  AND LOWER(c.medium)                   = cck.medium_lc
INNER JOIN rent_sale_shares rss
  ON  ADD_MONTHS(DATE_TRUNC('month', c.date), -1) = rss.year_month
  AND LOWER(c.city_group)               = LOWER(rss.city_group)
  AND LOWER(c.campaign_landing_page)    = LOWER(rss.campaign_landing_page)
  AND LOWER(c.campaign_business_context)= LOWER(rss.campaign_business_context)
  AND LOWER(c.source)                   = LOWER(rss.source)
  AND LOWER(c.medium)                   = LOWER(rss.medium)
INNER JOIN prospect_dist pd
  ON  ADD_MONTHS(DATE_TRUNC('month', c.date), -1) = pd.year_month
  AND LOWER(c.city_group)               = LOWER(pd.city_group)
  AND LOWER(c.campaign_landing_page)    = LOWER(pd.campaign_landing_page)
  AND LOWER(c.campaign_business_context)= LOWER(pd.campaign_business_context)
  AND LOWER(c.source)                   = LOWER(pd.source)
  AND LOWER(c.medium)                   = LOWER(pd.medium)
  -- Para campanha Rent pura: só liga com prospects RENT
  -- Para campanha Sale pura: só liga com prospects SALE
  -- Para Hybrid: liga com RENT e SALE (gera duas linhas por combo)
  AND (
    (LOWER(c.campaign_business_context) = 'rent' AND pd.nm_business_context = 'RENT')
    OR (LOWER(c.campaign_business_context) = 'sale' AND pd.nm_business_context = 'SALE')
    OR  LOWER(c.campaign_business_context) = 'hybrid'
  )

UNION ALL

-- =============================================================================
-- FALLBACK RENT: custos sem dados de prospects no mês anterior.
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
  'Rent'                               AS nm_business_context_mkt,
  NULL                                 AS company_report_origin,
  NULL                                 AS planning_cluster,
  c.source,
  c.medium,
  c.funnel_side,
  c.behavior_type,
  CASE
    WHEN LOWER(c.campaign_business_context) = 'rent' THEN c.costs
    ELSE c.costs * 0.5
  END                                  AS shared_cost
FROM costs c
LEFT JOIN covered_cost_keys cck
  ON  ADD_MONTHS(DATE_TRUNC('month', c.date), -1) = cck.ref_year_month
  AND LOWER(c.city_group)               = cck.city_group_lc
  AND LOWER(c.campaign_landing_page)    = cck.campaign_landing_page_lc
  AND LOWER(c.campaign_business_context)= cck.campaign_business_context_lc
  AND LOWER(c.source)                   = cck.source_lc
  AND LOWER(c.medium)                   = cck.medium_lc
WHERE cck.ref_year_month IS NULL
  AND LOWER(c.campaign_business_context) IN ('rent', 'hybrid')

UNION ALL

-- =============================================================================
-- FALLBACK SALE: custos sem dados de prospects no mês anterior.
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
  'Sale'                               AS nm_business_context_mkt,
  NULL                                 AS company_report_origin,
  NULL                                 AS planning_cluster,
  c.source,
  c.medium,
  c.funnel_side,
  c.behavior_type,
  CASE
    WHEN LOWER(c.campaign_business_context) = 'sale' THEN c.costs
    ELSE c.costs * 0.5
  END                                  AS shared_cost
FROM costs c
LEFT JOIN covered_cost_keys cck
  ON  ADD_MONTHS(DATE_TRUNC('month', c.date), -1) = cck.ref_year_month
  AND LOWER(c.city_group)               = cck.city_group_lc
  AND LOWER(c.campaign_landing_page)    = cck.campaign_landing_page_lc
  AND LOWER(c.campaign_business_context)= cck.campaign_business_context_lc
  AND LOWER(c.source)                   = cck.source_lc
  AND LOWER(c.medium)                   = cck.medium_lc
WHERE cck.ref_year_month IS NULL
  AND LOWER(c.campaign_business_context) IN ('sale', 'hybrid')
