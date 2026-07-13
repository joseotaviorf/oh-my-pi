WITH agent_updated AS (
    SELECT DISTINCT
        a.id AS id_agent
    FROM
        datalake_ebdb_clean.agent AS a
    WHERE
        DATE(a.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
agent_data_updated AS (
    SELECT DISTINCT
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
        aer.id_agent,
        FIRST(aer.value) FILTER(WHERE aer.type = 'DADOS_AGENTE_ID') AS id_agent_data,
        FIRST(u.id) AS id_user
    FROM
        datalake_ebdb_clean.agent_external_reference AS aer
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON CAST(aer.value AS BIGINT) = u.id_agent
            AND aer.type = 'DADOS_AGENTE_ID'
    GROUP BY
        aer.id_agent
),
legacy_agent_data_business_contexts AS (
    SELECT
        aud.id_agent_data,
        aud.business_context,
        aud.rev_type,
        ROW_NUMBER() OVER(PARTITION BY aud.id_agent_data, DATE(u.ts_revision) ORDER BY u.ts_revision DESC) = 1 AS is_last_update_by_date,
        u.ts_revision AS ts_revision_started,
        COALESCE(
            LEAD(u.ts_revision) OVER (PARTITION BY aud.id_agent_data, aud.business_context ORDER BY u.ts_revision) - INTERVAL 1 DAY,
            '{load_end_date}'
        ) AS ts_revision_ended
    FROM
        agent_data_updated AS ad
    JOIN
        datalake_ebdb_clean.agent_data_business_contexts_served_aud AS aud
            ON ad.id_agent_data = aud.id_agent_data
    JOIN 
        datalake_ebdb_user.user_revision_entity AS u 
            ON u.id = aud.rev
),
new_business_contexts AS (
    SELECT
        XXHASH64(settings.id_agent, settings.business_context, settings.ts_started) AS id_agent_business_context,
        settings.id_agent,
        agent.id_agent_data,
        agent.id_user,
        settings.business_context,
        "AGENT_DOMAIN" AS system_name,
        settings.ts_started AS ts_revision_started,
        COALESCE(settings.ts_ended - INTERVAL 1 DAY, '{load_end_date}') AS ts_revision_ended
    FROM
        agent_updated AS updated
    JOIN
        datalake_ebdb_agent_events.capability_settings AS settings
            ON updated.id_agent = settings.id_agent
    JOIN
        agent_external_reference AS agent
            ON updated.id_agent = agent.id_agent
    WHERE
        settings.is_last_update_by_date IS TRUE
),
legacy_business_contexts AS (
    SELECT
        XXHASH64(bc.id_agent_data, bc.business_context, bc.ts_revision_started) AS id_agent_business_context,
        new.id_agent,
        bc.id_agent_data,
        user.id AS id_user,
        bc.business_context,
        "LEGACY_SYSTEM" AS system_name,
        bc.ts_revision_started,
        bc.ts_revision_ended
    FROM
        legacy_agent_data_business_contexts AS bc
    LEFT JOIN
        datalake_ebdb_clean.user AS user
            ON user.id_agent = bc.id_agent_data
    LEFT JOIN
        new_business_contexts AS new
            ON new.id_agent_data = bc.id_agent_data
    WHERE
        bc.rev_type <> 2
        AND bc.is_last_update_by_date IS TRUE
        AND (
            new.id_agent_data IS NULL
            OR bc.ts_revision_started < new.ts_revision_started
        )
)
SELECT
    id_agent_business_context,
    id_agent,
    id_agent_data,
    id_user,
    business_context,
    system_name,
    ts_revision_started,
    ts_revision_ended
FROM
    new_business_contexts
UNION ALL
SELECT
    id_agent_business_context,
    id_agent,
    id_agent_data,
    id_user,
    business_context,
    system_name,
    ts_revision_started,
    ts_revision_ended
FROM
    legacy_business_contexts
