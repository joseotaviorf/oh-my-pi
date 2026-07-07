WITH agent_external_reference AS (
    SELECT
        aer.id_agent,
        FIRST(aer.value) FILTER(WHERE aer.type = 'DADOS_AGENTE_ID') AS id_agent_data,
        FIRST(aer.value) FILTER(WHERE aer.type = 'PARTNER_ID') AS id_partner
    FROM
        datalake_ebdb_clean.agent_external_reference AS aer
    GROUP BY ALL
),
main_user AS (
    WITH main_user_ranked AS (
        SELECT
            p.uuid_person,
            cr.id_reference AS id_user,
            ROW_NUMBER() OVER(PARTITION BY p.id ORDER BY cr.ts_updated DESC) AS rn
        FROM
            datalake_person_clean.person AS p
        JOIN
            datalake_person_clean.credential_reference AS cr
                ON cr.id_person = p.id
        WHERE
            cr.origin = 'main'
    )
    SELECT
        uuid_person,
        id_user
    FROM
        main_user_ranked
    WHERE
        rn = 1
),
agent AS (
    SELECT
        a.id AS id_agent,
        a.uuid_agent,
        a.uuid_person,
        aer.id_agent_data,
        aer.id_partner,
        mu.id_user,
        FIRST(a.id_partnership_representative) FILTER(WHERE a.partnership_representative_type = 'COMPANY_UUID') AS uuid_company,
        a.affiliation_type,
        a.status,
        COALESCE(a.affiliation_type = 'AUTONOMOUS', FALSE) AS is_1p_partnership,
        COALESCE(a.affiliation_type = 'COMPANY_MANAGED', FALSE) AS is_3p_partnership,
        a.ts_created,
        a.ts_updated
    FROM
        datalake_ebdb_clean.agent AS a
    LEFT JOIN
        agent_external_reference AS aer
            ON aer.id_agent = a.id
    LEFT JOIN
        main_user AS mu
            ON mu.uuid_person = a.uuid_person
    GROUP BY ALL
),
agent_product AS (
    WITH agent_product_ranked AS (
        SELECT
            a.id_agent,
            p.name AS company_product_name,
            CASE
                WHEN p.name IN ('Rede Sale', 'Rede Rent') THEN 'REDE'
                WHEN p.name IN ('PRO_ACQUIRER_AGENT', 'PRO_ACQUIRER_MANAGER_AGENT') THEN 'PRO_ACQUIRER'
                ELSE p.name
            END AS profile,
            ROW_NUMBER() OVER(PARTITION BY a.id_agent ORDER BY p.ts_updated DESC) AS rn
        FROM
            agent AS a
        JOIN
            datalake_company_clean.company AS c
                ON c.uuid_company = a.uuid_company
        JOIN
            datalake_company_clean.member_profile AS mp
                ON mp.id_company = c.id
                AND mp.uuid_person = a.uuid_person
        JOIN
            datalake_company_clean.product AS p
                ON p.id = mp.id_product
    )
    SELECT
        id_agent,
        company_product_name,
        profile
    FROM
        agent_product_ranked
    WHERE
        rn = 1
),
agent_parent_user AS (
    WITH member_profile AS (
        SELECT
            mp.id,
            mp.id_parent_member_profile,
            u.id_main_user AS id_user,
            mp.profile,
            mp.is_active,
            mp.ts_created
        FROM
            datalake_hub_services_clean.member_profile AS mp
        JOIN
            datalake_hub_services.users AS u
                ON u.id_user = mp.id_user
    ),
    agent_parent_user_ranked AS (
        SELECT
            mp.id_user,
            mp_parent.id_user AS id_parent_user,
            ROW_NUMBER() OVER(PARTITION BY mp.id_user ORDER BY mp.ts_created DESC) AS rn
        FROM
            member_profile AS mp
        JOIN
            member_profile AS mp_parent
                ON mp_parent.id = mp.id_parent_member_profile
        WHERE
            mp.profile = "AGENT"
            AND mp.is_active IS TRUE
            AND mp_parent.profile = "NEGOTIATION_EXECUTIVE"
    )
    SELECT
        id_user,
        id_parent_user
    FROM
        agent_parent_user_ranked
    WHERE
        rn = 1
),
agent_log AS (
    WITH agent_log_ranked AS (
        SELECT
            id_agent,
            event_type = 'AGENT_REACTIVATED' AS is_reactivated,
            LAG(ts_started) OVER(PARTITION BY id_agent ORDER BY ts_started) AS ts_previous_event_agent,
            ts_started AS ts_last_status_changed,
            TIMESTAMPDIFF(DAY, ts_started, NOW()) AS days_in_current_status,
            ROW_NUMBER() OVER(PARTITION BY id_agent ORDER BY ts_started DESC) AS rn
        FROM
            datalake_agent_accreditation.agent_event_log
        WHERE
            id_capability IS NULL
            AND event_type IN ('AGENT_ACTIVATED', 'AGENT_INACTIVATED', 'AGENT_REACTIVATED')
    )
    SELECT
        id_agent,
        is_reactivated,
        ts_previous_event_agent,
        ts_last_status_changed,
        days_in_current_status
    FROM
        agent_log_ranked
    WHERE
        rn = 1
),
agent_capability AS (
    SELECT
        c.id_agent,
        c.type,
        c.status,
        cs.business_context,
        cs.is_passive_lead_receiver,
        c.ts_created
    FROM
        datalake_ebdb_clean.capability AS c
    LEFT JOIN
        datalake_ebdb_clean.demand_visit_management_capability_settings AS cs
            ON c.id = cs.id_capability
),
capability_by_agent AS (
    SELECT
        id_agent,
        MAX(ts_created) FILTER(WHERE type = 'SUPPLY_ACQUISITION') IS NOT NULL AS is_allow_supply_acquisition,
        MAX(ts_created) FILTER(WHERE type = 'DEMAND_ACQUISITION') IS NOT NULL AS is_allow_demand_acquisition,
        MAX(ts_created) FILTER(WHERE type = 'DEMAND_VISIT_MANAGEMENT') IS NOT NULL AS is_allow_visit,
        MAX(business_context) FILTER(WHERE type = 'DEMAND_VISIT_MANAGEMENT' AND business_context = 'SALE') IS NOT NULL AS is_allow_demand_sale,
        MAX(business_context) FILTER(WHERE type = 'DEMAND_VISIT_MANAGEMENT' AND business_context = 'RENT') IS NOT NULL AS is_allow_demand_rent,
        MAX(is_passive_lead_receiver) FILTER(WHERE type = 'DEMAND_VISIT_MANAGEMENT') IS TRUE AS is_passive_lead_receiver
    FROM
        agent_capability
    WHERE
        status = 'ENABLED'
    GROUP BY 1
)
SELECT
    a.id_agent,
    a.id_agent_data,
    a.id_partner,
    a.id_user,
    apu.id_parent_user AS id_negotiation_executive_user,
    a.uuid_company,
    a.uuid_agent,
    a.uuid_person,
    pa.creci,
    pa.creci_uf,
    a.affiliation_type,
    a.status,
    ap.company_product_name,
    ap.profile,
    al.is_reactivated,
    ca.is_allow_supply_acquisition,
    ca.is_allow_demand_acquisition,
    ca.is_allow_visit,
    ca.is_allow_demand_sale,
    ca.is_allow_demand_rent,
    ca.is_passive_lead_receiver,
    a.is_1p_partnership,
    a.is_3p_partnership,
    al.days_in_current_status,
    al.ts_last_status_changed,
    a.ts_created,
    a.ts_updated
FROM
    agent AS a
LEFT JOIN
    datalake_agent_accreditation.prospect_agent AS pa
        ON pa.uuid_person = a.uuid_person
        AND pa.is_last_prospect_person_converted
LEFT JOIN
    agent_product AS ap
        ON ap.id_agent = a.id_agent
LEFT JOIN
    agent_parent_user AS apu
        ON apu.id_user = a.id_user
LEFT JOIN
    capability_by_agent AS ca
        ON ca.id_agent = a.id_agent
LEFT JOIN
    agent_log AS al
        ON al.id_agent = a.id_agent
