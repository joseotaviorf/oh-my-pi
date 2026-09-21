WITH agent_history AS (
    SELECT
        ac.id_snapshot,
        ac.id_unified_agent,
        ac.uuid_person,
        ac.profile,
        ac.is_active,
        ac.is_passive_lead_receiver,
        ac.is_allow_supply_acquisition,
        ac.is_allow_demand_visit_management,
        ac.is_allow_demand_sale,
        ac.is_allow_demand_rent,
        ac.is_allow_demand_acquisition,
        ac.is_allow_supply_conversion_consultancy,
        ac.is_allow_supply_representative,
        ac.is_allow_supply_midia_management,
        ac.is_allow_supply_integrity_assurance,
        ac.is_allow_negotiation,
        ac.has_rent_lead_referral,
        ac.has_rent_lead_referral_confirmed,
        ac.has_sale_lead_referral,
        ac.has_sale_lead_referral_confirmed,
        ac.dt_reference
    FROM
        datalake_agent_accreditation.agent_history AS ac
    WHERE
        DATE(ac.dt_reference) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
accreditation_date AS (
    SELECT
        events.id_unified_agent,
        MIN(events.ts_created) AS ts_first_activation
    FROM
        datalake_ebdb_agent_events.agent_accreditation_events AS events
    WHERE 
        events.event = "ACTIVATED"
    GROUP BY 1
),
agent_accreditation AS (
    SELECT
        ac.id_snapshot,
        MAX(ac.is_active IS TRUE AND COALESCE(DATE(ad.ts_first_activation) = ac.dt_reference, FALSE)) AS is_first_activation,
        MAX(ac.is_active IS TRUE AND COALESCE(DATE(ad.ts_first_activation) <> ac.dt_reference, FALSE)) AS is_reactivated,
        MAX(events.event_reason IN ("LEGACY_AGENT_MIGRATION", "LEGACY_AGENT_MIGRATION_BACKFILL")) AS is_legacy_agent_migrated,
        MAX(events.event_reason = "AGENT_DEACCREDITATION") AS is_deaccredited,
        MAX(events.event_reason = "INACTIVE_AGENT_REENROLLMENT") AS is_agent_reenrolled
    FROM
        agent_history AS ac
    JOIN
        datalake_ebdb_agent_events.agent_accreditation_events AS events
            ON events.id_unified_agent = ac.id_unified_agent
            AND ac.dt_reference = DATE(events.ts_created)
    LEFT JOIN
        accreditation_date AS ad
            ON events.id_unified_agent = ad.id_unified_agent
    GROUP BY 1
),
tier AS (
    SELECT
        ah.id_snapshot,
        MAX(pt.id_tier) FILTER(WHERE pt.incentive_system = 'DEMAND_CONVERSION_FR') AS sk_tier_demand_conversion_fr,
        MAX(pt.id_tier) FILTER(WHERE pt.incentive_system = 'DEMAND_CONVERSION_FS') AS sk_tier_demand_conversion_fs
    FROM
        agent_history AS ah
    JOIN
        datalake_big_agent.partner_tier AS pt
            ON ah.uuid_person = pt.uuid_person
            AND ah.dt_reference >= pt.dt_validity_started
            AND ah.dt_reference <= pt.dt_validity_ended
    WHERE
        pt.is_valid
    GROUP BY 1
)
SELECT
    ac.id_snapshot AS sk_agent_daily,
    a.sk_person,
    a.id_agent AS sk_agent,
    a.id_agent_data AS sk_agent_data,
    a.id_partner AS sk_partner,
    a.id_user AS sk_user,
    COALESCE(a.sk_broker, -1) AS sk_broker,
    a.uuid_person,
    t.sk_tier_demand_conversion_fr,
    t.sk_tier_demand_conversion_fs,
    ac.profile,
    ac.is_active AS is_agent_active,
    aa.is_reactivated,
    aa.is_first_activation,
    aa.is_deaccredited,
    aa.is_legacy_agent_migrated,
    aa.is_agent_reenrolled,
    ac.is_passive_lead_receiver,
    ac.is_allow_demand_acquisition,
    ac.is_allow_demand_visit_management AS is_allow_demand_visit,
    ac.is_allow_demand_sale,
    ac.is_allow_demand_rent,
    ac.is_allow_supply_acquisition,
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
    ac.dt_reference AS dt_ref,
    ac.dt_reference,
    YEAR(ac.dt_reference) AS year,
    MONTH(ac.dt_reference) AS month,
    DAY(ac.dt_reference) AS day
FROM
    agent_history AS ac
JOIN
    datalake_ebdb_agent_events.agent_unified_identity AS a
        ON a.id_unified_agent = ac.id_unified_agent
LEFT JOIN
    agent_accreditation AS aa
        ON ac.id_snapshot = aa.id_snapshot
LEFT JOIN
    tier AS t
        ON t.id_snapshot = ac.id_snapshot