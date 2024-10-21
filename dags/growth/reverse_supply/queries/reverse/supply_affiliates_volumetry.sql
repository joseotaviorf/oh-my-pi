WITH

--------- CÓDIGO PARA USAR A FATO DE EVENTOS AO INVÉS DA OBT, JÁ QUE ESTE DATAMART É USADO PARA CONSTRUIR OUTRO CAMPOS NA OBT ---------
descartes AS (
    SELECT 
        fse.sk_supply,
        fse.sk_date,
        ROW_NUMBER() OVER (PARTITION BY fse.sk_supply, fse.nm_business_context ORDER BY fse.ts_event DESC) AS discard_order,
        fse.nm_business_context
    FROM 
        dw_growth.fact_supply_events AS fse
    LEFT JOIN 
        dw_growth.dim_funnel_step AS dfs
            ON dfs.sk_funnel_step = fse.sk_funnel_step
    WHERE dfs.tp_business_event = 'drop'
    QUALIFY discard_order = 1
),
status AS (
  SELECT
        olc.id_lead,
        ROW_NUMBER() OVER (PARTITION BY id_lead ORDER BY olc.ts_call_started) first_call
    FROM
        datalake_olos_dialer.outbound_contact_attempts AS olc
    QUALIFY first_call = 1
),
base AS (
    SELECT
        dd.date,
        dd.week_start,
        dd.month_start,
        fse.sk_user_affiliate,
        fse.nm_business_context,
        dfs.cd_funnel_step,
        dsof.nm_assigned_partner,
        ddd.date AS discard_date,
        CAST(fse.sk_lead AS BIGINT) AS sk_lead,
        COALESCE(dsrf.tp_reprocessing, '-1') AS tp_reprocessing,
        CASE
            WHEN dsupc.tp_origin = 'admin_confirmation' THEN 'ciq'
            WHEN dsupc.tp_origin = 'portfolio_manager' THEN 'ciq'
            WHEN dsupc.tp_origin = 'consultantpwa' THEN 'ciq'
            WHEN dsupc.tp_origin = 'supplyprocessor' THEN 'rede'
            WHEN dsof.nm_agent IS NOT NULL THEN 'operations'
            WHEN dsupc.tp_origin IN ('full_self_service', 'referral', 'ios') THEN 'ownerpwa'
            WHEN dsupc.tp_origin IN ('prime','owner_conversion') THEN 'operations'
            ELSE concat('notmapped-',dsupc.tp_origin)
        END AS conversion_origin,
        CASE
            WHEN fse.nm_supply_source = '3P' THEN 'rede'
            WHEN fse.nm_supply_source = 'CIQ' THEN 'ciq'
            WHEN fse.sk_user_affiliate > -1 AND (dsupa.tp_origin not in ('consultantpwa', 'supplyprocessor')) THEN 'referrals'
            WHEN dsupa.tp_origin = 'app' THEN 'referrals'
            WHEN dsupa.tp_origin = 'whatsapp' THEN 'test'
            WHEN dsupa.tp_origin IN ('facebookleads', 'ownerpwa', 'landingproowners', 'landing', 'facebook', 'i24', 'ios') THEN 'ownerlanding'
            WHEN dsupa.tp_origin = 'humancrawler' THEN 'crawler'
            WHEN dsupa.tp_origin = 'supplyprocessor' THEN 'rede'
            WHEN dsupa.tp_origin = 'consultantpwa' THEN 'ciq'
            WHEN dsupa.tp_origin IN ('inbound', 'ownerconversionpwa') THEN 'operations'
            WHEN dsupa.tp_origin IN ('pricesuggestionsale', 'pricesuggestion') THEN dsupa.tp_origin
            WHEN dsupa.tp_origin IN ('ownerpropertyregistration', 'ownerhomeloggedin') THEN 'ownerpropertyregistration'
            ELSE concat('notmapped-',dsupa.tp_origin)
        END AS acquisition_origin,
        CASE
            WHEN dsupc.tp_origin = 'inbound' THEN 'is_inbound'
            WHEN dsupa.tp_origin = 'inbound' THEN 'is_inbound'
            WHEN dsupc.tp_origin = 'admin_confirmation' THEN 'ciq'
            WHEN dsupc.tp_origin = 'portfolio_manager' THEN 'ciq'
            WHEN dsof.nm_agent IS NULL AND dsupc.tp_origin = 'prime' THEN 'account_manager_pp_multi'
            WHEN dsof.nm_agent IS NULL AND dsupc.tp_origin = 'referral' THEN 'agent_indicacao_completa'
            ELSE dsof.nm_agent 
        END AS operation_channel,
        CASE
            WHEN dfs.cd_funnel_step = 'lead' THEN 1
            WHEN dfs.cd_funnel_step = 'prospect' THEN 2
            WHEN dfs.cd_funnel_step = 'qualified' THEN 3
            WHEN dfs.cd_funnel_step = 'av_qualified' THEN 4
            WHEN dfs.cd_funnel_step = 'opportunity' THEN 5
            WHEN dfs.cd_funnel_step = 'first_listing' THEN 6
        END AS funnel_order,
        fse.sk_supply
    FROM
        dw_growth.fact_supply_events AS fse
    LEFT JOIN 
        dw_growth.dim_funnel_step AS dfs
            ON fse.sk_funnel_step = dfs.sk_funnel_step
    LEFT JOIN 
        descartes AS dsd
            ON fse.sk_supply = dsd.sk_supply
            AND fse.nm_business_context = dsd.nm_business_context
    LEFT JOIN 
        dw_growth.dim_supply_operation_flow AS dsof 
            ON fse.sk_ops = dsof.sk_ops
    LEFT JOIN 
        dw_growth.dim_supply_recovery_flow AS dsrf
            ON fse.sk_recovery = dsrf.sk_recovery
    LEFT JOIN 
        dw_growth.dim_supply_user_path dsupa
            ON fse.sk_acquisition_user_path = dsupa.sk_user_path
            AND (dsupa.id_level = 1)
    LEFT JOIN 
        dw_growth.dim_supply_user_path dsupc
            ON fse.sk_conversion_user_path = dsupc.sk_user_path
    LEFT JOIN 
        dw_public.dim_date dd
            ON CAST(fse.sk_date AS INTEGER) = dd.sk_date
    LEFT JOIN 
        dw_public.dim_date ddd
            ON CAST(dsd.sk_date AS INTEGER) = ddd.sk_date
    WHERE fse.sk_funnel_step IN (5,9,2,10,7,12)
),
report_origin AS (
    SELECT
        obt.*,
        LAST_VALUE(obt.conversion_origin) OVER (PARTITION BY obt.sk_supply, obt.nm_business_context ORDER BY obt.funnel_order ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS full_conversion_origin,
        CASE
            WHEN obt.discard_date IS NOT NULL THEN 'discarded'
            WHEN opp.sk_supply IS NOT NULL THEN 'converted opp'
            WHEN olc.id_lead IS NOT NULL THEN 'started prospecting'
            ELSE 'new lead'
        END AS status
    FROM 
        base AS obt
    LEFT JOIN 
        dw_growth.fact_supply_events AS opp
            ON opp.sk_supply = obt.sk_supply
            AND opp.nm_business_context = obt.nm_business_context
            AND opp.sk_funnel_step = 7 -- only opportunity events
    LEFT JOIN 
        status AS olc
            ON olc.id_lead = obt.sk_lead
),
refact_obt_supply AS (
SELECT 
    week_start,
    month_start,
    sk_user_affiliate,
    nm_business_context,
    cd_funnel_step,
    funnel_order,
    status,
    sk_supply,
    CASE
        WHEN tp_reprocessing <> '-1' THEN 'IS'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'capta_ai' THEN 'Capta Aí'
        WHEN full_conversion_origin = 'operations' AND operation_channel IN ('asp','prime', 'account_manager_pp_multi') THEN 'PP Multi'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'is_inbound' THEN 'IS'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'is_outbound' THEN 'IS'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'is_expert' THEN 'IS'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'primary_market_bh' THEN 'Mercado Primário BH'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'ciq' THEN 'CIQ'
        WHEN full_conversion_origin = 'other' AND nm_assigned_partner = 'mensageria' THEN 'Mensageria'
        WHEN full_conversion_origin = 'operations' AND nm_assigned_partner = 'mensageria' THEN 'Mensageria'
        WHEN full_conversion_origin = 'operations' THEN 'IS'
        WHEN full_conversion_origin = 'ownerpwa' AND operation_channel = 'is_expert' THEN 'IS'
        WHEN full_conversion_origin = 'ownerpwa' AND operation_channel IN ('asp','prime', 'account_manager_pp_multi') THEN 'PP Multi'
        WHEN full_conversion_origin = 'ownerpwa' AND operation_channel = 'capta_ai' THEN 'Capta Aí'
        WHEN full_conversion_origin = 'ownerpwa' AND operation_channel = 'is_inbound' THEN 'IS'
        WHEN full_conversion_origin = 'ownerpwa' THEN 'FSS'
        WHEN full_conversion_origin = 'rede' THEN 'Rede'
        WHEN full_conversion_origin = 'ciq' THEN 'CIQ'
        WHEN nm_assigned_partner = 'mensageria' THEN 'Mensageria'
        WHEN nm_assigned_partner IS NOT NULL THEN 'IS'
        WHEN acquisition_origin = 'operations' AND operation_channel = 'is_inbound' THEN 'IS'
        WHEN acquisition_origin = 'rede' THEN 'Rede'
        WHEN acquisition_origin = 'ciq' THEN 'CIQ'
        ELSE 'Not Mapped' 
    END AS planning_conversion
FROM
    report_origin AS obt
),
--------- CÓDIGO PARA CALCULAR VOLUMETRIA DE AFILIADOS SEMANAL PARA INSIDE SALES (NSS) ---------
obt_cohort AS (
  SELECT
    obt1.sk_supply,
    obt1.sk_user_affiliate,
    obt1.status,
    obt1.planning_conversion,
    CAST(CONCAT(CAST(obt1.funnel_order AS STRING), '0', COALESCE(CAST(obt2.funnel_order AS STRING), '0')) AS INTEGER) AS cohort_funnel_order,
    obt1.week_start AS base_event_week,
    obt2.planning_conversion AS opp_conversion
  FROM refact_obt_supply AS obt1
    LEFT JOIN refact_obt_supply AS obt2
      ON obt1.sk_supply = obt2.sk_supply
      AND obt1.nm_business_context = obt2.nm_business_context
      AND obt1.funnel_order < obt2.funnel_order
),
obt_supply_filtered AS (
  SELECT
    base_event_week AS week_start,
    sk_user_affiliate,
    COUNT(DISTINCT (IF(cohort_funnel_order IN (200, 203),sk_supply, NULL))) AS prospects,
    COUNT(DISTINCT (IF(cohort_funnel_order=205, sk_supply, NULL))) AS opportunities
  FROM obt_cohort
  WHERE sk_user_affiliate > 0
    AND status IN ('converted opp', 'discarded')
    AND planning_conversion = 'IS'
  GROUP BY
    base_event_week,
    sk_user_affiliate
),
affiliates AS (
  SELECT 
    dat.sk_user_affiliate,
    dd.week_start
  FROM dw_growth.dim_affiliate_tracking dat
  JOIN dw_public.dim_date dd
    ON TRUE
  WHERE dat.sk_end_date IS NULL
    AND dd.date = dd.week_start
    AND dd.date > DATE('2020-01-01')
    AND dd.date <= CURRENT_DATE() 
),
base_all_weeks AS (
  SELECT
    a.week_start,
    a.sk_user_affiliate,
    SUM(prospects) AS prospects,
    SUM(opportunities) AS opportunities
  FROM affiliates a
  LEFT JOIN obt_supply_filtered obt
    ON obt.week_start = a.week_start
    AND obt.sk_user_affiliate = a.sk_user_affiliate
  GROUP BY
    a.week_start,
    a.sk_user_affiliate
),
metrics AS (
  SELECT 
    week_start,
    sk_user_affiliate,
    SUM(prospects) OVER (PARTITION BY sk_user_affiliate ORDER BY week_start ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) AS prospects_2weeks,
    SUM(opportunities) OVER (PARTITION BY sk_user_affiliate ORDER BY week_start ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) AS opportunities_2weeks,
    SUM(prospects) OVER (PARTITION BY sk_user_affiliate ORDER BY week_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS prospects_lifetime,
    SUM(opportunities) OVER (PARTITION BY sk_user_affiliate ORDER BY week_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS opportunities_lifetime
  FROM base_all_weeks
),
last_week AS (
  SELECT
    week_start,
    sk_user_affiliate,
    LAG(prospects_2weeks) OVER (PARTITION BY sk_user_affiliate ORDER BY week_start) AS prospects_l2w,
    LAG(opportunities_2weeks) OVER (PARTITION BY sk_user_affiliate ORDER BY week_start) AS opp_l2w,
    LAG(prospects_lifetime) OVER (PARTITION BY sk_user_affiliate ORDER BY week_start) AS lifetime_prospects_lw,
    LAG(opportunities_lifetime) OVER (PARTITION BY sk_user_affiliate ORDER BY week_start) AS lifetime_opp_lw
  FROM metrics
),
agg_metrics AS (
  SELECT
    week_start,
    sk_user_affiliate,
    SUM(prospects_l2w) AS prospects_l2w,
    SUM(opp_l2w) AS opp_l2w,
    SUM(opp_l2w)/SUM(prospects_l2w) AS p2o_l2w,
    SUM(lifetime_prospects_lw) AS lifetime_prospects,
    SUM(lifetime_opp_lw) AS lifetime_opp,
    SUM(lifetime_opp_lw)/SUM(lifetime_prospects_lw) AS lifetime_p2o
  FROM last_week
  GROUP BY
    week_start,
    sk_user_affiliate
),
volumetry AS (
    SELECT
        week_start,
        sk_user_affiliate,
        CASE
            WHEN COALESCE(prospects_l2w, 0) = 0 AND lifetime_p2o > 0.090 THEN 'Alta Conversão'
            WHEN COALESCE(prospects_l2w, 0) = 0 AND lifetime_p2o > 0.029 THEN 'Média Conversão'
            WHEN COALESCE(prospects_l2w, 0) = 0 AND lifetime_p2o > 0.015 THEN 'Baixa Conversão'
            WHEN prospects_l2w IS NULL THEN 'Baixíssima Conversão'
            WHEN p2o_l2w > 0.090 THEN 'Alta Conversão'
            WHEN p2o_l2w > 0.029 THEN 'Média Conversão'
            WHEN p2o_l2w > 0.015 THEN 'Baixa Conversão' 
            ELSE 'Baixíssima Conversão' 
        END AS affiliate_volumetry
    FROM 
        agg_metrics
)

SELECT 
    sk_user_affiliate AS affiliateId,
    affiliate_volumetry AS affiliateCategory
FROM 
    volumetry
WHERE 
    date_trunc('WEEK', NOW()) = week_start
GROUP BY ALL
UNION ALL
-- PARTNERS
SELECT
    EXPLODE(ARRAY(360754,912255,1711931,2257503)) AS affiliateId,
    'Baixíssima Conversão' AS affiliateCategory