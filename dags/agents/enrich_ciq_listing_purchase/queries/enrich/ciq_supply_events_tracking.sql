WITH supply_events_tracking AS (
    SELECT
        MD5(CONCAT_WS('#', COALESCE(supp.sk_supply_lead, -1), COALESCE(supp.id_house, -1))) AS id_supply,
        MD5(supp.supply_source) AS id_supply_source,
        supp.sk_supply_lead AS id_supply_lead,
        h.id_user AS id_owner,
        supp.id_house,
        COALESCE(supp.id_referred_by, -1) AS id_user_affiliate,
        COALESCE(supp.id_user_registrant, -1) AS id_user_registrant,
        COALESCE(supp.id_user_conversion, -1) AS id_user_conversion,
        supp.application,
        supp.platform,
        supp.ops_agent,
        supp.business_event,
        supp.aux_origin_table AS funnel_event_type,
        lower(supp.funnel_step) AS funnel_step,
        CASE
        WHEN lower(supp.funnel_step) = 'lead' AND supp.business_event = 'acquisition_tof2l' THEN 1
        WHEN lower(supp.funnel_step) = 'prospect' AND supp.business_event = 'conversion_l2p' THEN 2
        WHEN lower(supp.funnel_step) = 'qualified' AND supp.business_event = 'conversion_p2q' THEN 3
        WHEN lower(supp.funnel_step) = 'av_qualified' AND supp.business_event = 'conversion_q2aq' THEN 4
        WHEN lower(supp.funnel_step) = 'opportunity' AND supp.business_event = 'conversion_aq2o' THEN 5
        WHEN lower(supp.funnel_step) = 'first_listing' AND supp.business_event = 'conversion_o2fl' THEN 6
        ELSE -1
        END AS id_funnel_step,
        supp.business_context,
        supp.supply_source,
        supp.ts_event_adjusted AS ts_event
    FROM
        datalake_supply_flows.supply_events_tracking AS supp
    LEFT JOIN 
        datalake_ebdb_listing.house AS h
        ON supp.id_house = h.id
    WHERE supp.business_event IN ('acquisition_tof2l','conversion_l2p','conversion_p2q','conversion_q2aq','conversion_aq2o','conversion_o2fl') 
    -- Eqquivalent to Lead / Prospect / Qualified / Av. Qualified / Opportunity / First Listing

),
union_events AS (
    SELECT
        *,
        CASE
        WHEN supply_source = '3P' OR application = 'supplyprocessor' THEN 'rede'
        WHEN supply_source = 'CIQ' OR application = 'consultantpwa' THEN 'ciq'
        WHEN id_user_affiliate > -1 AND (application not in ('consultantpwa', 'supplyprocessor')) THEN 'referrals'
        WHEN application = 'app' THEN 'referrals'
        WHEN application = 'whatsapp' THEN 'test'
        WHEN application IN ('facebookleads', 'ownerpwa', 'landingproowners', 'landing', 'facebook', 'i24', 'ios') THEN 'ownerlanding'
        WHEN application = 'humancrawler' THEN 'crawler'
        WHEN application IN ('inbound', 'ownerconversionpwa') THEN 'operations'
        WHEN application IN ('pricesuggestionsale', 'pricesuggestion') THEN application
        WHEN application IN ('ownerpropertyregistration', 'ownerhomeloggedin') THEN 'ownerpropertyregistration'
        ELSE concat('notmapped-', application)
        END AS origin
    FROM
        supply_events_tracking
    WHERE
        funnel_event_type = 'acquisition'
    UNION ALL
    SELECT
        *,
        CASE
        WHEN application IN ('admin_confirmation','portfolio_manager','consultantpwa') THEN 'ciq'
        WHEN application = 'supplyprocessor' THEN 'rede'
        WHEN ops_agent IS NOT NULL THEN 'operations'
        WHEN application IN ('full_self_service', 'referral', 'ios') THEN 'ownerpwa'
        WHEN application IN ('prime','owner_conversion') THEN 'operations'
        ELSE concat('notmapped-', application)
        END AS origin
    FROM
        supply_events_tracking
    WHERE
        funnel_event_type = 'conversion'

),
additional_funnel_rules AS (
    SELECT 
        *,
        CASE
            WHEN origin = 'ciq' THEN 'CIQ'
            WHEN origin = 'operations' AND (application IN ('admin_confirmation','portfolio_manager','consultantpwa') OR ops_agent = 'ciq') THEN 'CIQ - Operations'
            ELSE 'Other'
        END AS company_report_origin
    FROM 
        union_events
)
SELECT 
    id_supply,
    id_supply_lead,
    id_supply_source,
    id_owner,
    id_house,
    id_user_affiliate,
    id_user_registrant,
    id_user_conversion,
    id_funnel_step,
    ops_agent,
    funnel_step,
    funnel_event_type,
    business_event,
    origin,
    business_context,
    supply_source,
    application,
    platform,
    company_report_origin,
    ts_event
FROM 
    additional_funnel_rules 
