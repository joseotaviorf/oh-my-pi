WITH agent_updated AS (
    SELECT
        a.id AS id_agent,
        a.uuid_person
    FROM
        datalake_ebdb_clean.agent AS a
    WHERE
        DATE(a.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
agent_data_updated AS (
    SELECT
        aud.id_agent_data
    FROM
        datalake_ebdb_user.user_revision_entity AS u
    JOIN
        datalake_ebdb_clean.agent_data_business_contexts_served_aud AS aud
            ON u.id = aud.rev
    WHERE
        DATE(u.ts_revision) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
agent_external_reference AS (
    SELECT
        ps.uuid_person,
        ps.id_user,
        agent.id_agent,
        u.id_agent AS id_agent_data
    FROM
        datalake_person.person_sks AS ps
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON u.id = ps.id_user
    LEFT JOIN
        agent_updated AS agent
            ON agent.uuid_person = ps.uuid_person
    LEFT JOIN
        agent_data_updated AS legacy_agent
            ON legacy_agent.id_agent_data = u.id_agent
    WHERE
        COALESCE(agent.id_agent, legacy_agent.id_agent_data) IS NOT NULL
    GROUP BY 1, 2, 3, 4
),
legacy_agent_data_business_contexts AS (
    SELECT
        aud.id_agent_data,
        aer.id_user,
        aer.uuid_person,
        aud.business_context,
        aud.rev_type,
        ROW_NUMBER() OVER(PARTITION BY aud.id_agent_data, DATE(u.ts_revision) ORDER BY u.ts_revision DESC) = 1 AS is_last_update_by_date,
        u.ts_revision AS ts_revision_started
    FROM
        agent_external_reference AS aer
    JOIN
        datalake_ebdb_clean.agent_data_business_contexts_served_aud AS aud
            ON aer.id_agent_data = aud.id_agent_data
    JOIN 
        datalake_ebdb_user.user_revision_entity AS u 
            ON u.id = aud.rev
),
new_business_contexts AS (
    SELECT
        XXHASH64(aer.uuid_person, settings.id_agent, settings.business_context, DATE(settings.ts_started)) AS id_agent_business_context,
        settings.id_agent,
        aer.id_agent_data,
        aer.id_user,
        aer.uuid_person,
        settings.business_context,
        "AGENT_DOMAIN" AS system_name,
        ROW_NUMBER() OVER (PARTITION BY settings.id_agent ORDER BY settings.ts_started) = 1 AS is_first_event,
        settings.ts_started AS ts_revision_started
    FROM
        agent_external_reference AS aer
    JOIN
        datalake_ebdb_agent_events.capability_settings AS settings
            ON settings.id_agent = aer.id_agent
    WHERE
        settings.is_last_update_by_date IS TRUE
),
legacy_business_contexts AS (
    SELECT
        XXHASH64(bc.uuid_person, new.id_agent, bc.business_context, DATE(bc.ts_revision_started)) AS id_agent_business_context,
        new.id_agent,
        bc.id_agent_data,
        bc.id_user,
        bc.uuid_person,
        bc.business_context,
        "LEGACY_SYSTEM" AS system_name,
        bc.ts_revision_started
    FROM
        legacy_agent_data_business_contexts AS bc
    LEFT JOIN
        new_business_contexts AS new
            ON new.id_agent_data = bc.id_agent_data
            AND new.is_first_event IS TRUE
    WHERE
        bc.rev_type <> 2
        AND bc.is_last_update_by_date IS TRUE
        AND (
            new.id_agent_data IS NULL
            OR DATE(bc.ts_revision_started) < DATE(new.ts_revision_started)
        )
),
business_contexts AS (
    SELECT
        id_agent_business_context,
        id_agent,
        id_agent_data,
        id_user,
        uuid_person,
        business_context,
        system_name,
        ts_revision_started
    FROM
        new_business_contexts
    UNION
    SELECT
        id_agent_business_context,
        id_agent,
        id_agent_data,
        id_user,
        uuid_person,
        business_context,
        system_name,
        ts_revision_started
    FROM
        legacy_business_contexts
)
SELECT
    id_agent_business_context,
    id_agent,
    id_agent_data,
    id_user,
    uuid_person,
    business_context,
    system_name,
    ts_revision_started,
    LEAD(ts_revision_started) OVER (PARTITION BY id_user, id_agent ORDER BY ts_revision_started) - INTERVAL 1 DAY AS ts_revision_ended
FROM
    business_contexts