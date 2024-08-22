WITH descartes AS (
    SELECT 
        fse.sk_supply,
        fse.sk_date,
        ROW_NUMBER() OVER (PARTITION BY fse.sk_supply, fse.nm_business_context ORDER BY fse.ts_event DESC) AS discard_order,
        fse.nm_business_context,
        dsd.cd_funnel_step,
        dsd.cd_discard_reason,
        dsd.ds_discard_reason,
        dsof.nm_agent,
        dsof.nm_partner,
        dsof.nm_assigned_partner
    FROM 
        dw_growth.fact_supply_events AS fse
    LEFT JOIN 
        dw_growth.dim_supply_discards AS dsd 
            ON fse.sk_discard = dsd.sk_discard
    LEFT JOIN 
        dw_growth.dim_funnel_step AS dfs
            ON dfs.sk_funnel_step = fse.sk_funnel_step
    LEFT JOIN 
        dw_growth.dim_supply_operation_flow AS dsof 
            ON fse.sk_ops = dsof.sk_ops
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
        dd.year_month,
        dd.sk_date,
        dr.city_group,
        dr.city_name,
        dr.name AS neighborhood,
        dr.country_code,
        dr.id_country,
        CAST(fse.sk_lead AS BIGINT) AS sk_lead,
        fse.sk_house,
        fse.sk_region,
        fse.sk_funnel_step,
        fse.sk_user_affiliate,
        fse.sk_user_conversion,
        fse.sk_user_registrant,
        fse.sk_owner,
        fse.nm_business_context,
        fse.nm_supply_source,
        fse.utm_source AS nm_source,
        fse.utm_medium AS nm_medium,
        fse.utm_campaign AS nm_campaign,
        dal.tp_lead,
        dfs.cd_funnel_step,
        dfs.tp_business_event,
        dms.campaign_strategy_intent,
        dms.campaign_business_context,
        dms.campaign_landing_page,
        dms.source,
        dms.medium,
        dms.behavior_type,
        dms.funnel_side,
        dsd.cd_discard_reason,
        dsd.ds_discard_reason,
        dsd.cd_funnel_step AS discard_funnel_step,
        dsd.nm_agent discard_agent,
        dsd.nm_partner discard_partner,
        dsd.nm_assigned_partner as discard_assigned_partner,
        ddd.date AS discard_date,
        ddd.year_month AS discard_year_month,
        dsof.ds_objective,
        dsof.nm_agent,
        dsof.nm_partner,
        dsof.nm_assigned_partner,
        dsof.cd_contact_medium,
        dsof.cd_approach,
        COALESCE(dsrf.tp_reprocessing, '-1') AS tp_reprocessing,
        dsrf.nm_mailing_table,
        dsupa.tp_origin as tp_origin_acquisition,
        dsupc.tp_origin as tp_origin_conversion,
        LAST_VALUE(dsupc.tp_origin) OVER (PARTITION BY fse.sk_supply, fse.sk_house, fse.nm_business_context ORDER BY dsupc.id_level) AS full_tp_origin_conversion,
        CASE
            WHEN fse.sk_user_affiliate IN (360754,912255,1711931,2257503) THEN 'partner'
            WHEN LOWER(dat.affiliate_type) = 'doorman' AND dd.sk_date > 20230531 THEN 'standard'
            ELSE LOWER(dat.affiliate_type)
        END AS affiliate_type_adjusted,
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
        fse.sk_supply,
        ac.affiliate_campaign,
        ac.affiliate_objective
    FROM
        dw_growth.fact_supply_events AS fse 
    LEFT JOIN
        dw_growth.dim_acquisition_lead AS dal
            ON fse.sk_acquisition_lead = dal.sk_acquisition_lead
    LEFT JOIN 
        dw_growth.dim_affiliate_tracking AS dat
            ON (fse.sk_user_affiliate = dat.sk_user_affiliate)
            AND (fse.ts_first_event_date >= dat.ts_started)
            AND (fse.ts_first_event_date < COALESCE(dat.ts_ended, CAST('2099-12-31' AS TIMESTAMP)))
    LEFT JOIN 
        dw_growth.dim_funnel_step AS dfs
            ON fse.sk_funnel_step = dfs.sk_funnel_step
    LEFT JOIN 
        dw_growth.dim_media_setup AS dms
            ON fse.sk_media_setup = dms.sk_media_setup
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
    LEFT JOIN 
        dw_public.dim_region dr
            ON fse.sk_region = dr.sk_region
    LEFT JOIN 
        datalake_growth_taxonomy.affiliates_classification AS ac
            ON dat.sk_user_affiliate = ac.sk_user_affiliate
    WHERE fse.sk_funnel_step IN (5,9,2,10,7,12)
),
report_origin AS (
    SELECT
        obt.*,
        CASE
            WHEN obt.funnel_order > 2 AND obt.tp_reprocessing <> '-1' THEN 'Reprocessamento'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'rede' THEN 'Rede'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'ciq' THEN 'CIQ'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'operations' AND obt.operation_channel = 'ciq' THEN 'CIQ'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'operations' AND obt.operation_channel = 'capta_ai' THEN 'Capta Aí'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'operations' AND obt.operation_channel IN ('asp', 'account_manager_pp_multi') THEN 'PP Multi'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'operations' AND obt.operation_channel = 'is_expert' THEN 'IS Expert'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'ownerlanding' AND lower(obt.medium) = 'seo non-branded' THEN 'Owner PWA - Organic'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'ownerlanding' AND lower(obt.source) = 'braze' THEN 'Owner PWA - CRM/Notification'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'ownerlanding' AND lower(obt.behavior_type) = 'non organic' THEN 'Owner PWA - Paid'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'ownerlanding' AND lower(obt.behavior_type) = 'organic' THEN 'Owner PWA - Organic'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'ownerlanding' THEN 'Owner PWA - Not Mapped'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'ownerpropertyregistration' AND lower(obt.medium) = 'seo non-branded' THEN 'Owner PWA - Organic'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'ownerpropertyregistration' AND lower(obt.source) = 'braze' THEN 'Owner PWA - CRM/Notification'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'ownerpropertyregistration' AND lower(obt.behavior_type) = 'non organic' THEN 'Owner PWA - Paid'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'ownerpropertyregistration' AND lower(obt.behavior_type) = 'organic' THEN 'Owner PWA - Organic'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'ownerpropertyregistration' THEN 'Owner PWA - Not Mapped'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'pricesuggestion' THEN 'Price Calculator'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'pricesuggestionsale' THEN 'Price Calculator - Sale'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'referrals' AND obt.affiliate_type_adjusted = 'agent' THEN 'Indica Aí - Agents'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'referrals' AND obt.affiliate_type_adjusted IN ('doorman', 'B2B Partner') THEN 'Doorman/B2B'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'referrals' AND obt.affiliate_type_adjusted = 'partner' THEN 'Partners'
            WHEN obt.funnel_order > 2 AND obt.acquisition_origin = 'referrals' THEN 'Indica Aí - General'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'operations' AND obt.operation_channel = 'is_inbound' THEN 'Inbound'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'operations' THEN 'Backend'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'rede' THEN 'Rede'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ciq' THEN 'CIQ'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'operations' AND obt.operation_channel = 'ciq' THEN 'CIQ'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'operations' AND obt.operation_channel = 'capta_ai' THEN 'Capta Aí'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'operations' AND obt.operation_channel IN ('asp', 'account_manager_pp_multi') THEN 'PP Multi'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'operations' AND obt.operation_channel = 'is_expert' THEN 'IS Expert'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ownerlanding' AND lower(obt.medium) = 'seo non-branded' THEN 'Owner PWA - Organic'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ownerlanding' AND lower(obt.source) = 'braze' THEN 'Owner PWA - CRM/Notification'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ownerlanding' AND lower(obt.behavior_type) = 'non organic' THEN 'Owner PWA - Paid'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ownerlanding' AND lower(obt.behavior_type) = 'organic' THEN 'Owner PWA - Organic'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ownerlanding' THEN 'Owner PWA - Not Mapped'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ownerpropertyregistration' AND lower(obt.medium) = 'seo non-branded' THEN 'Owner PWA - Organic'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ownerpropertyregistration' AND lower(obt.source) = 'braze' THEN 'Owner PWA - CRM/Notification'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ownerpropertyregistration' AND lower(obt.behavior_type) = 'non organic' THEN 'Owner PWA - Paid'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ownerpropertyregistration' AND lower(obt.behavior_type) = 'organic' THEN 'Owner PWA - Organic'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'ownerpropertyregistration' THEN 'Owner PWA - Not Mapped'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'pricesuggestion' THEN 'Price Calculator'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'pricesuggestionsale' THEN 'Price Calculator - Sale'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'referrals' AND obt.affiliate_type_adjusted = 'agent' THEN 'Indica Aí - Agents'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'referrals' AND obt.affiliate_type_adjusted IN ('doorman', 'B2B Partner') THEN 'Doorman/B2B'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'referrals' AND obt.affiliate_type_adjusted = 'partner' THEN 'Partners'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'referrals' THEN 'Indica Aí - General'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'operations' AND obt.operation_channel = 'is_inbound' THEN 'Inbound'
            WHEN obt.funnel_order < 3 AND obt.acquisition_origin = 'operations' THEN 'Backend'
            -- Adjusting cases without leads
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'ownerpwa' AND obt.acquisition_origin = 'notmapped-notmapped' THEN 'Owner PWA - Not Mapped'
            -- Adjusting cases with leads equal other
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'ownerpwa' AND lower(obt.medium) = 'seo non-branded' THEN 'Owner PWA - Organic'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'ownerpwa' AND lower(obt.source) = 'braze' THEN 'Owner PWA - CRM/Notification'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'ownerpwa' AND lower(obt.behavior_type) = 'non organic' THEN 'Owner PWA - Paid'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'ownerpwa' AND lower(obt.behavior_type) = 'organic' THEN 'Owner PWA - Organic'
            WHEN obt.funnel_order > 2 AND obt.conversion_origin = 'ownerpwa' THEN 'Owner PWA - Not Mapped'
            ELSE 'Other'
        END AS company_report_origin,
        LAST_VALUE(obt.conversion_origin) OVER (PARTITION BY obt.sk_supply, obt.nm_business_context ORDER BY obt.funnel_order ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS full_conversion_origin,
        LAST_VALUE(obt.operation_channel) OVER (PARTITION BY obt.sk_supply, obt.nm_business_context ORDER BY obt.funnel_order ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS full_operation_channel,
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
)

SELECT 
    obt.*,
    CASE
        WHEN company_report_origin = 'Indica Aí - General' AND affiliate_volumetry = 'Novos Afiliados' THEN 'Indica Aí - General_Novo Afiliado'
        WHEN company_report_origin = 'Indica Aí - General' AND affiliate_volumetry = 'AAVs BH' THEN 'Indica Aí - General_Afiliados_BH'
        WHEN company_report_origin = 'Indica Aí - General' AND affiliate_volumetry = 'Outros AAVs' THEN 'Indica Aí - General_Afiliados_Alto_Volume'
        WHEN company_report_origin = 'Indica Aí - General' THEN 'Indica Aí - General_Baixo Volume'
        WHEN company_report_origin = 'Owner PWA - Paid' AND lower(medium) = 'web display' THEN 'Owner PWA - Paid_Display'
        WHEN company_report_origin = 'Owner PWA - Paid' AND lower(medium) = 'sem non-branded' THEN 'Owner PWA - Paid_SEM non-branded'
        WHEN company_report_origin = 'Owner PWA - Paid' AND lower(medium) = 'performance max' THEN 'Owner PWA - Paid_Performance_Max'
        WHEN company_report_origin = 'Owner PWA - Paid' THEN 'Owner PWA - Paid_Other Paid'
        WHEN company_report_origin IN ('Price Calculator', 'Price Calculator - Sale') AND lower(source) = 'braze' THEN CONCAT(company_report_origin, '_CRM/Notification')
        WHEN company_report_origin IN ('Price Calculator', 'Price Calculator - Sale') AND lower(behavior_type) = 'organic' THEN CONCAT(company_report_origin, '_Organic')
        WHEN company_report_origin IN ('Price Calculator', 'Price Calculator - Sale') AND lower(behavior_type) = 'non organic' AND lower(medium) = 'web display' THEN CONCAT(company_report_origin, '_Display')
        WHEN company_report_origin IN ('Price Calculator', 'Price Calculator - Sale') AND lower(behavior_type) = 'non organic' AND lower(medium) = 'sem non-branded' THEN CONCAT(company_report_origin, '_SEM non-branded')
        WHEN company_report_origin IN ('Price Calculator', 'Price Calculator - Sale') AND lower(behavior_type) = 'non organic' AND lower(medium) = 'performance max' THEN CONCAT(company_report_origin, '_Performance_Max')
        WHEN company_report_origin IN ('Price Calculator', 'Price Calculator - Sale') THEN CONCAT(company_report_origin, '_Other Paid')
        ELSE company_report_origin
    END AS planning_cluster,
    CASE
        WHEN tp_reprocessing <> '-1' THEN 'Outbound'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'capta_ai' THEN 'Capta Aí'
        WHEN full_conversion_origin = 'operations' AND operation_channel IN ('prime','account_manager_pp_multi','asp') THEN 'PP Multi'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'is_inbound' THEN 'Inbound'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'is_outbound' THEN 'Outbound'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'is_expert' THEN 'IS Expert'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'primary_market_bh' THEN 'Mercado Primário BH'
        WHEN full_conversion_origin = 'operations' AND operation_channel = 'ciq' THEN 'CIQ'
        WHEN full_conversion_origin = 'other' AND nm_assigned_partner = 'mensageria' THEN 'Mensageria'
        WHEN full_conversion_origin = 'operations' AND nm_assigned_partner = 'mensageria' THEN 'Mensageria'
        WHEN full_conversion_origin = 'operations' THEN 'Outbound'
        WHEN full_conversion_origin = 'ownerpwa' AND operation_channel = 'is_expert' THEN 'IS Expert'
        WHEN full_conversion_origin = 'ownerpwa' AND operation_channel IN ('asp','prime', 'account_manager_pp_multi') THEN 'PP Multi'
        WHEN full_conversion_origin = 'ownerpwa' AND operation_channel = 'capta_ai' THEN 'Capta Aí'         
        WHEN full_conversion_origin = 'ownerpwa' AND operation_channel = 'is_inbound' THEN 'Inbound'
        WHEN full_conversion_origin = 'ownerpwa' THEN 'FSS'
        WHEN full_conversion_origin = 'rede' THEN 'Rede'
        WHEN full_conversion_origin = 'ciq' THEN 'CIQ'
        WHEN nm_assigned_partner = 'mensageria' THEN 'Mensageria'
        WHEN nm_assigned_partner IS NOT NULL THEN 'Outbound'
        WHEN acquisition_origin = 'operations' AND operation_channel = 'is_inbound' THEN 'Inbound'
        WHEN acquisition_origin = 'rede' THEN 'Rede'
        WHEN acquisition_origin = 'ciq' THEN 'CIQ'
        ELSE 'Not Mapped'
    END AS planning_operation,
    CASE
        WHEN company_report_origin IN ('Backend','Other','Owner PWA - CRM/Notification','Owner PWA - Not Mapped','Owner PWA - Organic') THEN 'High'
        WHEN company_report_origin IN ('Indica Aí - Agents','Owner PWA - Paid','Price Calculator','Price Calculator - Sale') THEN 'Low'
        WHEN company_report_origin = 'Partners' THEN 'Very low'
        WHEN company_report_origin = 'Indica Aí - General' AND affiliate_volumetry = 'AAVs BH' THEN 'Very low'
        WHEN company_report_origin = 'Indica Aí - General' AND affiliate_volumetry = 'Outros AAVs' THEN 'Very low'
        WHEN company_report_origin = 'Indica Aí - General' AND affiliate_volumetry = 'Novos Afiliados' THEN 'Average'
        WHEN company_report_origin = 'Indica Aí - General' THEN 'Average'    
        ELSE 'sem_cluster'
    END AS planning_conversion_cluster,
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
    END AS planning_conversion,
    NOW() AS ts_load
FROM
    report_origin AS obt
LEFT JOIN 
    dw_datamarts.affiliates_clusters AS ac 
        ON (ac.sk_user = obt.sk_user_affiliate)
        AND (ac.year_month = obt.year_month)