WITH agent AS (
    SELECT
        agent.id AS id_agent,
        FIRST(reference.value) FILTER (WHERE reference.type = 'DADOS_AGENTE_ID') AS id_agent_data,
        FIRST(reference.value) FILTER (WHERE reference.type = 'PARTNER_ID') AS id_partner,
        FIRST(reference.value) FILTER (WHERE reference.type = 'PROSPECT_UUID') AS uuid_prospect,
        FIRST(agent.id_partnership_representative) FILTER(WHERE agent.partnership_representative_type = 'COMPANY_UUID') AS uuid_company,
        agent.uuid_agent,
        agent.uuid_person,
        agent.affiliation_type,
        agent.status,
        COALESCE(agent.affiliation_type = 'AUTONOMOUS', FALSE) AS is_1p_partnership,
        COALESCE(agent.affiliation_type = 'COMPANY_MANAGED', FALSE) AS is_3p_partnership,
        agent.ts_created,
        agent.ts_updated
    FROM
        datalake_ebdb_clean.agent AS agent
    LEFT JOIN
        datalake_ebdb_clean.agent_external_reference AS reference
            ON reference.id_agent = agent.id
    GROUP BY 1, 6, 7, 8, 9, 10, 11, 12, 13
),
agent_data AS (
    SELECT
        agent_data.id AS id_agent_data,
        agent_data.uuid_company,
        agent_data.creci_number,
        agent_data.is_active,
        agent_data.agent_type <> 'CORRETOR_REDE' AS is_1p_partnership,
        agent_data.agent_type = 'CORRETOR_REDE' AS is_3p_partnership,
        agent_data.ts_updated,
        agent_data.ts_created
    FROM
        datalake_ebdb_clean.agent_data AS agent_data
),
partner AS (
    SELECT
        partner.id AS id_partner,
        partner_agent.id AS id_partner_agent,
        partner_agent.id_user,
        partner.uuid_company,
        partner.creci,
        partner_agent.status,
        partner.ts_created,
        GREATEST(partner.ts_updated, partner_agent.ts_updated) AS ts_updated
    FROM
        datalake_ebdb_clean.partner AS partner
    JOIN
        datalake_ebdb_clean.partner_agent AS partner_agent
            ON partner_agent.id_partner = partner.id
),
person_creci_number AS (
    SELECT
        document.id_person,
        document.identification_number AS creci
    FROM
        datalake_person_clean.identity_document AS document
    WHERE
        document.document_type = "CRECI"
),
prospect_agent AS (
    SELECT
        prospect.id AS id_prospect_agent,
        prospect.uuid_prospect,
        prospect_creci.creci,
        prospect_creci.creci_uf
    FROM
        datalake_ebdb_clean.prospect_agent AS prospect
    JOIN
        datalake_ebdb_clean.quintoandar_prospect_agent AS prospect_creci
            ON prospect_creci.id_prospect_agent = prospect.id
),
person_data AS (
    SELECT
        person.sk_person,
        person.id_user,
        agent_data.id_agent_data AS id_agent_data,
        partner.id_partner AS id_partner,
        partner.id_partner_agent AS id_partner_agent,
        affiliate.id AS id_affiliate,
        user.id_photographer_data,
        COALESCE(agent_data.uuid_company, partner.uuid_company) AS uuid_company,
        person.uuid_person,
        COALESCE(
            person_creci.creci,
            agent_data.creci_number,
            partner.creci
        ) AS creci,
        affiliate.is_active AS is_affiliate_active,
        photographer.is_active AS is_photographer_active,
        agent_data.is_active AS is_agent_data_active,
        user.is_active AS is_user_active,
        partner.status = 'ACTIVE' AS is_partner_active,
        agent_data.is_1p_partnership,
        agent_data.is_3p_partnership,
        COALESCE(agent_data.ts_created, partner.ts_created) AS ts_created,
        COALESCE(agent_data.ts_updated, partner.ts_updated) AS ts_updated
    FROM
        datalake_person.person_sks AS person
    LEFT JOIN
        datalake_ebdb_clean.user AS user
            ON user.id = person.id_user
    LEFT JOIN
        agent AS agent
            ON agent.uuid_person = person.uuid_person
    LEFT JOIN
        agent_data AS agent_data
            ON agent_data.id_agent_data = user.id_agent
    LEFT JOIN
        partner AS partner
            ON partner.id_user = person.id_user
    LEFT JOIN
        datalake_ebdb_clean.affiliate_data AS affiliate
            ON affiliate.id_user = person.id_user
    LEFT JOIN
        datalake_ebdb_clean.photographer_data AS photographer
            ON photographer.id = user.id_photographer_data
    LEFT JOIN
        person_creci_number AS person_creci
            ON person_creci.id_person = person.id_person
    WHERE
        agent.id_agent IS NOT NULL
        OR agent_data.id_agent_data IS NOT NULL
        OR partner.id_partner IS NOT NULL
), 
unified_identity AS (
    SELECT
        person.sk_person,
        person.id_user,
        agent.id_agent,
        agent.id_agent_data,
        agent.id_partner,
        IF(agent.id_partner IS NOT NULL, person.id_partner_agent, NULL) AS id_partner_agent,
        prospect.id_prospect_agent,
        person.id_affiliate,
        person.id_photographer_data,
        CASE
            WHEN agent.uuid_company IS NOT NULL 
                THEN agent.uuid_company
            WHEN agent.uuid_company IS NULL
                AND COALESCE(agent.id_agent_data, agent.id_partner) IS NOT NULL 
                THEN person.uuid_company
        END AS uuid_company,
        agent.uuid_person,
        agent.uuid_agent,
        agent.uuid_prospect,
        COALESCE(person.creci, prospect.creci) AS creci,
        prospect.creci_uf,
        agent.id_agent_data IS NOT NULL AS is_agent_data_associated,
        agent.id_partner IS NOT NULL AS is_partner_associated,
        person.is_affiliate_active,
        person.is_photographer_active,
        person.is_user_active,
        agent.status = 'ACTIVE' AS is_agent_active,
        IF(agent.id_agent_data IS NOT NULL, person.is_agent_data_active, NULL) AS is_agent_data_active,
        IF(agent.id_partner IS NOT NULL, person.is_partner_active, NULL) AS is_partner_active,
        (
            agent.status = 'ACTIVE'
            OR (agent.id_agent_data IS NOT NULL AND person.is_agent_data_active IS TRUE)
            OR (agent.id_partner IS NOT NULL AND person.is_partner_active IS TRUE)
        ) AS is_unified_agent_active,
        COALESCE(agent.is_1p_partnership, person.is_1p_partnership) AS is_1p_partnership,
        COALESCE(agent.is_3p_partnership, person.is_3p_partnership) AS is_3p_partnership,
        IF(
            COALESCE(agent.id_agent_data, agent.id_partner) IS NOT NULL,
            LEAST(agent.ts_created, person.ts_created),
            agent.ts_created
        ) AS ts_created,
        GREATEST(agent.ts_updated, person.ts_updated) AS ts_updated
    FROM
        agent AS agent
    LEFT JOIN
        person_data AS person
            ON agent.uuid_person = person.uuid_person
    LEFT JOIN
        prospect_agent AS prospect
            ON prospect.uuid_prospect = agent.uuid_prospect
    UNION
    SELECT
        person.sk_person,
        person.id_user,
        NULL AS id_agent,
        MAX(IF(agent_data_exception.id_agent_data IS NULL, person.id_agent_data, NULL)) AS id_agent_data,
        MAX(IF(partner_exception.id_partner IS NULL, person.id_partner, NULL)) AS id_partner,
        MAX(IF(partner_exception.id_partner IS NULL, person.id_partner_agent, NULL)) AS id_partner_agent,
        NULL AS id_prospect_agent,
        person.id_affiliate,
        person.id_photographer_data,
        person.uuid_company,
        person.uuid_person,
        NULL AS uuid_agent,
        NULL AS uuid_prospect,
        person.creci,
        NULL AS creci_uf,
        FALSE AS is_agent_data_associated,
        FALSE AS is_partner_associated,
        person.is_affiliate_active,
        person.is_photographer_active,
        person.is_user_active,
        NULL AS is_agent_active,
        MAX(IF(agent_data_exception.id_agent_data IS NULL, person.is_agent_data_active, NULL)) AS is_agent_data_active,
        MAX(IF(partner_exception.id_partner IS NULL, person.is_partner_active, NULL)) AS is_partner_active,
        MAX(
            (agent_data_exception.id_agent_data IS NULL AND person.is_agent_data_active IS TRUE)
            OR (partner_exception.id_partner IS NULL AND person.is_partner_active IS TRUE)
        ) AS is_unified_agent_active,
        person.is_1p_partnership,
        person.is_3p_partnership,
        person.ts_created,
        person.ts_updated
    FROM
        person_data AS person
    LEFT JOIN
        agent AS agent_data_exception
            ON agent_data_exception.uuid_person = person.uuid_person
            AND agent_data_exception.id_agent_data = person.id_agent_data
    LEFT JOIN
        agent AS partner_exception
            ON partner_exception.uuid_person = person.uuid_person
            AND partner_exception.id_partner = person.id_partner
    WHERE
        agent_data_exception.id_agent_data IS NULL
        OR partner_exception.id_partner IS NULL
    GROUP BY 1, 2, 3, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 25, 26, 27, 28
),
brokers_profile AS (
    SELECT
        bp.sk_broker,
        bp.uuid_person,
        MAX(bp.profile_status = 'ACTIVE') AS has_3p_member_profile_active,
        MAX(bp.profile_status IN ('PENDING CONFIRMATION', 'PENDING INVITATION')) AS has_3p_member_profile_pending
    FROM
        core_brokers.brokers_profile AS bp
    WHERE
        bp.profile = 'third_party_agent'
    GROUP BY 1, 2
)
SELECT
    XXHASH64(
        COALESCE(p.uuid_person, ''),
        COALESCE(p.id_agent, -1),
        COALESCE(p.id_agent_data, -1),
        COALESCE(p.id_partner, -1)
    ) AS id_unified_agent,
    p.sk_person,
    p.id_user,
    p.id_agent,
    p.id_agent_data,
    p.id_partner,
    p.id_partner_agent,
    b.sk_broker,
    p.id_prospect_agent,
    p.id_affiliate,
    p.id_photographer_data,
    p.uuid_person,
    p.uuid_company,
    p.uuid_agent,
    p.uuid_prospect,
    p.creci,
    p.creci_uf,
    p.is_affiliate_active,
    p.is_photographer_active,
    p.is_user_active,
    p.is_partner_active,
    p.is_agent_data_active,
    p.is_agent_active,
    p.is_unified_agent_active,
    p.is_1p_partnership,
    p.is_3p_partnership,
    IF(
        p.is_unified_agent_active IS TRUE,
        ROW_NUMBER() OVER (
            PARTITION BY p.sk_person, p.is_unified_agent_active
            ORDER BY p.ts_updated DESC, p.ts_created DESC
        ) = 1,
        FALSE
    ) AS is_last_active_by_person,
    ROW_NUMBER() OVER (
        PARTITION BY p.id_agent_data 
        ORDER BY 
            p.is_agent_data_associated DESC, 
            p.is_unified_agent_active DESC,
            p.ts_updated DESC
    ) = 1 AS is_agent_data_replace_key,
    ROW_NUMBER() OVER (
        PARTITION BY p.id_partner 
        ORDER BY 
            p.is_partner_associated DESC, 
            p.is_unified_agent_active DESC, 
            p.ts_updated DESC
    ) = 1 AS is_partner_replace_key,
    bp.has_3p_member_profile_active,
    bp.has_3p_member_profile_pending,
    p.ts_created,
    p.ts_updated,
    YEAR(p.ts_created) AS year,
    MONTH(p.ts_created) AS month,
    DAY(p.ts_created) AS day
FROM
    unified_identity AS p
LEFT JOIN
    core_brokers.brokers AS b
        ON b.uuid_company = p.uuid_company
LEFT JOIN
    brokers_profile AS bp
        ON p.uuid_person = bp.uuid_person
        AND b.sk_broker = bp.sk_broker
WHERE
    COALESCE(p.id_agent, p.id_agent_data, p.id_partner) IS NOT NULL
