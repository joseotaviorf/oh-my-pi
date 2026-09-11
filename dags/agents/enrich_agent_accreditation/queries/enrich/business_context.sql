WITH agent_external_reference AS (
    SELECT
        aui.id_unified_agent,
        aui.id_user,
        aui.id_agent,
        aui.id_agent_data,
        aui.uuid_person,
        aui.is_agent_data_replace_key
    FROM
        datalake_ebdb_agent_events.agent_unified_identity AS aui
    LEFT JOIN
        datalake_ebdb_clean.agent_data_business_contexts_served AS legacy
            ON legacy.id_agent_data = aui.id_agent_data
    LEFT JOIN
        datalake_ebdb_agent_events.capability_settings AS current
            ON current.id_agent = aui.id_agent
    WHERE
        DATE(legacy.ts_database_transaction) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        OR DATE(current.ts_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY 1, 2, 3, 4, 5, 6
),
legacy_agent_data_business_contexts AS (
    SELECT
        aer.id_unified_agent,
        aer.id_user,
        aer.id_agent,
        aer.id_agent_data,
        aer.uuid_person,
        aud.business_context,
        aud.rev_type,
        -- rev_type ASC breaks ties between a transition's DEL (2) and ADD (0) row, which share the same instant 
        ROW_NUMBER() OVER (
            PARTITION BY aud.id_agent_data, CAST(u.ts_revision / 1000 AS TIMESTAMP)
            ORDER BY
                aud.rev_type ASC,
                CASE
                    WHEN aud.business_context = "SALE" THEN 1
                    WHEN aud.business_context = "SALE_PRIMARY_MARKET" THEN 2
                    ELSE 3
                END,
                aud.business_context DESC
        ) = 1 AS is_last_update_by_instant,
        CAST(u.ts_revision / 1000 AS TIMESTAMP) AS ts_revision_started
    FROM
        agent_external_reference AS aer
    JOIN
        datalake_ebdb_clean.agent_data_business_contexts_served_aud AS aud
            ON aer.id_agent_data = aud.id_agent_data
    JOIN
        datalake_ebdb_clean.user_revision_entity AS u
            ON u.id = aud.rev
    WHERE
        aer.is_agent_data_replace_key IS TRUE
),
-- one row per context run: drop DEL-only, then keep the ADD that starts a new
-- business_context. Same-day N switches become N sequential boxes 
legacy_context_changes AS (
    SELECT
        id_unified_agent,
        id_agent_data,
        id_agent,
        id_user,
        uuid_person,
        business_context,
        ts_revision_started
    FROM (
        SELECT
            id_unified_agent,
            id_agent_data,
            id_agent,
            id_user,
            uuid_person,
            business_context,
            ts_revision_started,
            LAG(business_context) OVER (
                PARTITION BY id_agent_data
                ORDER BY ts_revision_started
            ) AS previous_business_context
        FROM
            legacy_agent_data_business_contexts
        WHERE
            rev_type <> 2
            AND is_last_update_by_instant IS TRUE
    )
    WHERE
        previous_business_context IS NULL
        OR previous_business_context <> business_context
),
new_business_contexts AS (
    SELECT
        XXHASH64(aer.id_unified_agent, settings.business_context, settings.ts_started) AS id_agent_business_context,
        aer.id_unified_agent,
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
        XXHASH64(bc.id_unified_agent, bc.business_context, bc.ts_revision_started) AS id_agent_business_context,
        bc.id_unified_agent,
        bc.id_agent,
        bc.id_agent_data,
        bc.id_user,
        bc.uuid_person,
        bc.business_context,
        "LEGACY_SYSTEM" AS system_name,
        bc.ts_revision_started
    FROM
        legacy_context_changes AS bc
    LEFT JOIN
        new_business_contexts AS new
            ON new.id_agent_data = bc.id_agent_data
            AND new.is_first_event IS TRUE
    WHERE
        new.id_agent_data IS NULL
        OR bc.ts_revision_started < new.ts_revision_started
),
-- dedupe on the real merge key before ts_revision_ended's LEAD() below, else duplicate
-- rows sharing a key can invert that window and erase coverage 
business_contexts AS (
    SELECT 
        id_agent_business_context,
        id_unified_agent,
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
        id_unified_agent,
        id_agent,
        id_agent_data,
        id_user,
        uuid_person,
        business_context,
        system_name,
        ts_revision_started 
    FROM 
        legacy_business_contexts
),
mod_business_contexts AS (
    SELECT
        id_agent_business_context,
        id_unified_agent,
        id_agent,
        id_agent_data,
        id_user,
        uuid_person,
        business_context,
        system_name,
        COALESCE(LAG(business_context) OVER (PARTITION BY id_unified_agent, system_name ORDER BY ts_revision_started) <> business_context, TRUE) AS mod_business_context,
        ts_revision_started
    FROM
        business_contexts
)
SELECT
    id_agent_business_context,
    id_unified_agent,
    id_agent,
    id_agent_data,
    id_user,
    uuid_person,
    business_context,
    system_name,
    ROW_NUMBER() OVER(PARTITION BY uuid_person, CAST(ts_revision_started AS DATE) ORDER BY ts_revision_started DESC) = 1 AS is_latest_by_date,
    ts_revision_started,
    LEAD(ts_revision_started) OVER (PARTITION BY uuid_person ORDER BY ts_revision_started) AS ts_revision_ended
FROM
    mod_business_contexts
WHERE
    mod_business_context IS TRUE
