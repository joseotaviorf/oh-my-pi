WITH agent_accreditation_dates AS (
    SELECT
        events.id_unified_agent,
        MIN(events.ts_created) FILTER(WHERE events.event = "MIGRATED") AS ts_legacy_agent_migrated,
        MIN(events.ts_created) AS ts_accreditation,
        MIN(events.ts_created) FILTER(WHERE events.event = "ACTIVATED") AS ts_first_activation,
        MAX(events.ts_created) FILTER(WHERE (aui.is_unified_agent_active IS FALSE AND events.event = "INACTIVATED") OR events.event_reason = "AGENT_DEACCREDITATION") AS ts_deaccreditation,
        MIN(events.ts_created) FILTER(WHERE events.event_reason = "INACTIVE_AGENT_REENROLLMENT") AS ts_agent_reenrollment
    FROM
        datalake_ebdb_agent_events.agent_accreditation_events AS events
    JOIN
        datalake_ebdb_agent_events.agent_unified_identity AS aui
            ON events.id_unified_agent = aui.id_unified_agent
    GROUP BY 1
),
agent_accreditation AS (
    SELECT
        events.id_unified_agent,
        ROW_NUMBER() OVER (PARTITION BY events.id_unified_agent ORDER BY events.ts_created DESC) = 1 AS is_lastest_event,
        events.is_active IS TRUE AND ROW_NUMBER() OVER (PARTITION BY events.id_unified_agent ORDER BY events.ts_created) <> 1 AS is_reactivated,
        ABS(DATE_DIFF(
            COALESCE(
                LAG(events.ts_created) OVER (PARTITION BY events.id_unified_agent ORDER BY events.ts_created),
                NOW()
            ),
            events.ts_created
        )) AS days_in_current_status,
        events.ts_created AS ts_last_status_changed
    FROM
        datalake_ebdb_agent_events.agent_accreditation_events AS events
),
agent_history_last_reference AS (
    SELECT
        id_unified_agent,
        MAX(dt_reference) AS dt_lastest_reference
    FROM
        datalake_agent_accreditation.agent_history
    GROUP BY 1
)
SELECT
    a.sk_person,
    a.id_agent AS sk_agent,
    a.id_prospect_agent AS sk_prospect_agent,
    a.id_agent_data AS sk_agent_data,
    a.id_partner AS sk_partner,
    a.id_partner_agent AS sk_partner_agent,
    a.id_user AS sk_user,
    COALESCE(a.sk_broker, -1) AS sk_broker,
    a.id_affiliate AS sk_affiliate,
    a.id_photographer_data AS sk_photographer_data,
    a.sk_company,
    a.uuid_agent,
    a.creci,
    a.creci_uf,
    product.product_name AS profile,
    product.deactivation_reason,
    product.deactivation_sub_reason,
    aa.is_reactivated,
    a.is_agent_active,
    a.is_photographer_active,
    a.is_affiliate_active,
    ac.is_passive_lead_receiver,
    ac.is_allow_supply_acquisition,
    ac.is_allow_demand_visit_management AS is_allow_demand_visit,
    ac.is_allow_demand_sale,
    ac.is_allow_demand_rent,
    ac.is_allow_demand_acquisition,
    ac.is_allow_supply_conversion_consultancy AS is_allow_supply_conversion,
    ac.is_allow_supply_representative,
    ac.is_allow_supply_midia_management,
    ac.is_allow_supply_integrity_assurance,
    ac.is_allow_negotiation,
    a.is_1p_partnership,
    a.is_3p_partnership,
    ac.has_rent_lead_referral,
    ac.has_rent_lead_referral_confirmed,
    ac.has_sale_lead_referral,
    ac.has_sale_lead_referral_confirmed,
    aa.days_in_current_status,
    aa.ts_last_status_changed,
    aad.ts_accreditation,
    aad.ts_first_activation,
    aad.ts_deaccreditation,
    aad.ts_legacy_agent_migrated,
    aad.ts_agent_reenrollment,
    a.ts_created,
    a.ts_updated
FROM
    datalake_ebdb_agent_events.agent_unified_identity AS a
LEFT JOIN
    agent_history_last_reference AS last_ref
        ON a.id_unified_agent = last_ref.id_unified_agent
LEFT JOIN
    datalake_agent_accreditation.agent_history AS ac
        ON last_ref.id_unified_agent = ac.id_unified_agent
        AND last_ref.dt_lastest_reference = ac.dt_reference
LEFT JOIN
    agent_accreditation_dates AS aad
        ON a.id_unified_agent = aad.id_unified_agent
LEFT JOIN
    agent_accreditation AS aa
        ON a.id_unified_agent = aa.id_unified_agent
        AND aa.is_lastest_event IS TRUE
LEFT JOIN
    datalake_ebdb_agent_events.agent_product AS product
        ON a.id_agent = product.id_agent
        AND product.is_valid_product IS TRUE
        AND product.is_lastest_valid IS TRUE