WITH agent_accreditation_events AS (
    SELECT
        events.id_unified_agent,
        events.event,
        events.is_active,
        ROW_NUMBER() OVER (PARTITION BY events.id_unified_agent, DATE(events.ts_created) ORDER BY events.ts_created DESC) = 1 AS is_lastest_by_date,
        events.ts_created AS ts_started,
        COALESCE(LEAD(events.ts_created) OVER (PARTITION BY events.id_unified_agent ORDER BY events.ts_created) - INTERVAL 1 DAY, '{load_end_date}') AS ts_ended
    FROM
        datalake_ebdb_agent_events.agent_accreditation_events AS events
),
agent_base AS (
    SELECT
        aui.sk_person,
        events.id_unified_agent,
        aui.id_agent,
        aui.id_agent_data,
        aui.id_partner,
        aui.id_user,
        aui.sk_broker,
        aui.uuid_person,
        events.is_active,
        EXPLODE(SEQUENCE(
            DATE(events.ts_started), 
            DATE(
                IF(
                    events.event = "INACTIVATED",
                    events.ts_started,
                    events.ts_ended
                )
            )
        )) AS dt_reference
    FROM
        agent_accreditation_events AS events
    JOIN
        datalake_ebdb_agent_events.agent_unified_identity AS aui
            ON aui.id_unified_agent = events.id_unified_agent
    WHERE
        events.is_lastest_by_date IS TRUE
        AND (
            (
                events.event <> "INACTIVATED" 
                AND DATE(events.ts_started) <= DATE('{load_end_date}')
                AND DATE(events.ts_ended) >= DATE('{load_start_date}')
            )
            OR (
                events.event = "INACTIVATED" 
                AND DATE(events.ts_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
            )
        )
),
partner_type AS (
    SELECT
        events.id_partner,
        p.type = 'AUTONOMOUS_AGENT' AS is_allow_supply_acquisition,
        p.type = 'AUTONOMOUS_AGENT' AS is_allow_supply_conversion_consultancy,
        MIN(events.ts_created) AS ts_accreditation,
        MAX(events.ts_created) FILTER (WHERE events.event_reason = "AGENT_DEACCREDITATION" OR events.event = "INACTIVATED") AS ts_deaccreditation
    FROM
        agent_base AS base
    JOIN
        datalake_ebdb_agent_events.agent_accreditation_events AS events
            ON base.id_unified_agent = events.id_unified_agent
    JOIN
        datalake_ebdb_clean.partner AS p
            ON p.id = events.id_partner
    WHERE
        events.source = 'PARTNER_DATA'
    GROUP BY 1, 2, 3
),
daily_capability AS (
    SELECT
        c.id_agent,
        c.id_capability,
        c.type,
        c.business_context,
        c.is_capability_active,
        c.is_passive_lead_receiver,
        EXPLODE(SEQUENCE(DATE(c.ts_started), DATE(COALESCE(c.ts_ended, '{load_end_date}')))) AS dt_reference
    FROM
        agent_base AS base
    JOIN
        datalake_ebdb_agent_events.capability_events AS c
            ON base.id_agent = c.id_agent
    WHERE
        c.is_last_event_by_date IS TRUE
),
agent_capability AS (
    SELECT
        id_agent,
        dt_reference,
        MAX(business_context) AS business_context,
        MAX(NULLIF(business_context = "SALE", FALSE)) AS is_allow_demand_sale,
        MAX(NULLIF(business_context = "RENT", FALSE)) AS is_allow_demand_rent,
        MAX(is_passive_lead_receiver) AS is_passive_lead_receiver,
        MAX(is_allow_supply_acquisition) AS is_allow_supply_acquisition,
        MAX(is_allow_demand_visit_management) AS is_allow_demand_visit_management,
        MAX(is_allow_demand_acquisition) AS is_allow_demand_acquisition,
        MAX(is_allow_supply_conversion_consultancy) AS is_allow_supply_conversion_consultancy,
        MAX(is_allow_supply_representative) AS is_allow_supply_representative,
        MAX(is_allow_supply_midia_management) AS is_allow_supply_midia_management,
        MAX(is_allow_supply_integrity_assurance) AS is_allow_supply_integrity_assurance,
        MAX(is_allow_negociation) AS is_allow_negociation
    FROM 
        daily_capability
    PIVOT (
        MAX(is_capability_active)
        FOR type IN (
            "SUPPLY_ACQUISITION" AS is_allow_supply_acquisition,
            "DEMAND_VISIT_MANAGEMENT" AS is_allow_demand_visit_management,
            "DEMAND_ACQUISITION" AS is_allow_demand_acquisition,
            "SUPPLY_CONVERSION_CONSULTANCY" AS is_allow_supply_conversion_consultancy,
            "SUPPLY_REPRESENTATIVE" AS is_allow_supply_representative,
            "SUPPLY_MIDIA_MANAGEMENT" AS is_allow_supply_midia_management,
            "SUPPLY_INTEGRITY_ASSURANCE" AS is_allow_supply_integrity_assurance,
            "NEGOTIATION" AS is_allow_negociation
        )
    )
    GROUP BY 1, 2
),
business_context_daily AS (
    SELECT
        bc.id_unified_agent,
        MAX(business_context = "SALE") AS is_allow_demand_sale,
        MAX(business_context = "RENT") AS is_allow_demand_rent,
        EXPLODE(SEQUENCE(
            DATE(bc.ts_revision_started),
            DATE(COALESCE(
                bc.ts_revision_ended - INTERVAL 1 DAY,
                '{load_end_date}'
            ))
        )) AS dt_reference
    FROM
        agent_base AS base
    JOIN
        datalake_agent_accreditation.business_context AS bc
            ON base.id_unified_agent = bc.id_unified_agent
    WHERE
        bc.is_lastest_by_date IS TRUE
    GROUP BY 1, 4
),
agent_data_lead_receiver AS (
    SELECT
        ad.id AS id_agent_data,
        ad.is_passive_lead_receiver,
        COALESCE(LAG(ad.is_passive_lead_receiver) OVER (
            PARTITION BY ad.id 
            ORDER BY CAST(ure.ts_revision / 1000 AS TIMESTAMP)
        ), FALSE) <> ad.is_passive_lead_receiver AS mod_is_passive_lead_receiver,
        CAST(ure.ts_revision / 1000 AS TIMESTAMP) AS ts_revision
    FROM
        agent_base AS base
    JOIN
        datalake_ebdb_clean.agent_data_aud AS ad
            ON base.id_agent_data = ad.id
    JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ad.rev = ure.id
    WHERE
        ad.is_passive_lead_receiver IS NOT NULL
),
legacy_passive_lead_receiver AS (
    SELECT
        id_agent_data,
        is_passive_lead_receiver,
        ROW_NUMBER() OVER(PARTITION BY id_agent_data, DATE(ts_revision) ORDER BY ts_revision DESC) = 1 AS is_lastest_by_date,
        DATE(ts_revision) AS dt_started,
        DATE(LEAD(ts_revision) OVER(PARTITION BY id_agent_data ORDER BY ts_revision) - INTERVAL 1 DAY) AS dt_ended
    FROM
        agent_data_lead_receiver
    WHERE
        mod_is_passive_lead_receiver IS TRUE
),
agent_lead_referral AS (
    SELECT
        base.id_agent_data,
        MAX(COALESCE(aud.business_context, 'SALE') = 'SALE' AND aud.status <> 'NOT_ELIGIBLE') AS has_sale_lead_referral,
        MAX(COALESCE(aud.business_context, 'SALE') = 'SALE' AND aud.status = 'CONFIRMED') AS has_sale_lead_referral_confirmed,
        MAX(aud.business_context = 'RENT' AND aud.status <> 'NOT_ELIGIBLE') AS has_rent_lead_referral,
        MAX(aud.business_context = 'RENT' AND aud.status = 'CONFIRMED') AS has_rent_lead_referral_confirmed,
        CAST(CAST(ts_revision / 1000 AS TIMESTAMP) AS DATE) AS dt_reference
    FROM
        agent_base AS base
    JOIN
        datalake_ebdb_clean.agent_lead_referral_aud AS aud
            ON base.id_agent_data = aud.id_agent
    JOIN
        datalake_ebdb_clean.user_revision_entity AS rev
            ON rev.id = aud.rev 
    GROUP BY 1, 6
)
SELECT
    XXHASH64(base.id_unified_agent, base.dt_reference) AS id_snapshot,
    base.sk_person,
    base.id_unified_agent,
    base.id_agent,
    base.id_agent_data,
    base.id_partner,
    base.id_user,
    base.sk_broker,
    base.uuid_person,
    COALESCE(
        agent_cap.business_context, 
        IF(agent_bc.is_allow_demand_sale IS TRUE, 'SALE', NULL),
        IF(agent_bc.is_allow_demand_rent IS TRUE, 'RENT', NULL)
    ) AS business_context,
    base.is_active,
    MAX(COALESCE(receiver.is_passive_lead_receiver, agent_cap.is_passive_lead_receiver, FALSE)) AS is_passive_lead_receiver,
    MAX(COALESCE(agent_cap.is_allow_supply_acquisition, pt_type.is_allow_supply_acquisition, FALSE)) AS is_allow_supply_acquisition,
    MAX(COALESCE(agent_cap.is_allow_demand_visit_management, ag_type.profile = 'Visita', FALSE)) AS is_allow_demand_visit_management,
    MAX(COALESCE(agent_cap.is_allow_demand_sale, agent_bc.is_allow_demand_sale, FALSE)) AS is_allow_demand_sale,
    MAX(COALESCE(agent_cap.is_allow_demand_rent, agent_bc.is_allow_demand_rent, FALSE)) AS is_allow_demand_rent,
    MAX(COALESCE(agent_cap.is_allow_demand_acquisition, FALSE)) AS is_allow_demand_acquisition,
    MAX(COALESCE(agent_cap.is_allow_supply_conversion_consultancy, pt_type.is_allow_supply_conversion_consultancy, FALSE)) AS is_allow_supply_conversion_consultancy,
    MAX(COALESCE(agent_cap.is_allow_supply_representative, FALSE)) AS is_allow_supply_representative,
    MAX(COALESCE(agent_cap.is_allow_supply_midia_management, ag_type.profile = 'SessaoFotos', FALSE)) AS is_allow_supply_midia_management,
    MAX(COALESCE(agent_cap.is_allow_supply_integrity_assurance, ag_type.profile IN ('Vistoria', 'VistoriaQuarteirizada'), FALSE)) AS is_allow_supply_integrity_assurance,
    MAX(COALESCE(agent_cap.is_allow_negociation, FALSE)) AS is_allow_negociation,
    MAX(COALESCE(lead_referral.has_sale_lead_referral, FALSE)) AS has_sale_lead_referral,
    MAX(COALESCE(lead_referral.has_sale_lead_referral_confirmed, FALSE)) AS has_sale_lead_referral_confirmed,
    MAX(COALESCE(lead_referral.has_rent_lead_referral, FALSE)) AS has_rent_lead_referral,
    MAX(COALESCE(lead_referral.has_rent_lead_referral_confirmed, FALSE)) AS has_rent_lead_referral_confirmed,
    base.dt_reference
FROM
    agent_base AS base
LEFT JOIN
    agent_capability AS agent_cap
        ON base.id_agent = agent_cap.id_agent
        AND base.dt_reference = agent_cap.dt_reference
LEFT JOIN
    business_context_daily AS agent_bc
        ON base.id_unified_agent = agent_bc.id_unified_agent
        AND base.dt_reference = agent_bc.dt_reference
LEFT JOIN
    datalake_agent_accreditation.agent_profile AS ag_type
        ON base.id_agent_data = ag_type.id_agent_data
        AND base.dt_reference BETWEEN DATE(ag_type.ts_revision_started) AND DATE(COALESCE(ag_type.ts_revision_ended - INTERVAL 1 DAY, '{load_end_date}'))
        AND ag_type.is_lastest_by_date IS TRUE
LEFT JOIN
    partner_type AS pt_type
        ON base.id_partner = pt_type.id_partner
        AND base.dt_reference BETWEEN DATE(pt_type.ts_accreditation) AND DATE(COALESCE(pt_type.ts_deaccreditation, '{load_end_date}'))
LEFT JOIN
    legacy_passive_lead_receiver AS receiver
        ON base.id_agent_data = receiver.id_agent_data
        AND receiver.is_lastest_by_date IS TRUE
        AND base.dt_reference BETWEEN receiver.dt_started AND COALESCE(receiver.dt_ended, DATE('{load_end_date}'))
LEFT JOIN
    agent_lead_referral AS lead_referral
        ON base.id_agent_data = lead_referral.id_agent_data
        AND base.dt_reference >= lead_referral.dt_reference
WHERE
    base.dt_reference BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 27