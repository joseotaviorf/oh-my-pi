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
    SELECT
        p.uuid_person,
        cr.id_reference AS id_user
    FROM
        datalake_person_clean.person AS p
    JOIN
        datalake_person_clean.credential_reference AS cr
            ON cr.id_person = p.id
    WHERE
        cr.origin = 'main'
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY p.id ORDER BY cr.ts_updated DESC) = 1
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
        COALESCE(a.affiliation_type = 'COMPANY_MANAGED', FALSE) AS is_3_partnership,
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
    SELECT
        a.id_agent,
        p.name AS company_product_name
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
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY a.id_agent ORDER BY p.ts_updated DESC)
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
    )
    SELECT
        mp.id_user,
        mp_parent.id_user AS id_parent_user
    FROM 
        member_profile AS mp
    JOIN 
        member_profile AS mp_parent
            ON mp_parent.id = mp.id_parent_member_profile
    WHERE
        mp.profile = "AGENT"
        AND mp.is_active IS TRUE
        AND mp_parent.profile = "NEGOTIATION_EXECUTIVE"
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY mp.id_user ORDER BY mp.ts_created DESC)
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
    a.affiliation_type,
    a.status,
    ap.company_product_name,
    a.is_1p_partnership,
    a.is_3_partnership,
    a.ts_created,
    a.ts_updated
FROM
    agent AS a
LEFT JOIN
    agent_product AS ap
        ON ap.id_agent = a.id_agent
LEFT JOIN
    agent_parent_user AS apu
        ON apu.id_user = a.id_user