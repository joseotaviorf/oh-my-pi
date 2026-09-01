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
-- agent_unified_identity has a proper tiebreak per id_agent_data but only covers ~6.4k of
-- ~51k agents (no full backfill) -- not a usable substitute here (AAREDE-526).
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
        -- Same-instant multi-context ADDs: keep one row. Prefer ADD over DEL so a
        -- real transition stays visible, then SALE over other contexts (stakeholder
        -- mismatch / AAREDE-526).
        ROW_NUMBER() OVER (
            PARTITION BY aud.id_agent_data, u.ts_revision
            ORDER BY
                aud.rev_type ASC,
                CASE
                    WHEN aud.business_context = "SALE" THEN 1
                    WHEN aud.business_context = "SALE_PRIMARY_MARKET" THEN 2
                    ELSE 3
                END,
                aud.business_context DESC
        ) = 1 AS is_last_update_by_instant,
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
-- one row per context run: drop DEL-only, then keep the ADD that starts a new
-- business_context. Same-day N switches become N sequential boxes (AAREDE-526).
legacy_context_changes AS (
    SELECT
        id_agent_data,
        id_user,
        uuid_person,
        business_context,
        ts_revision_started
    FROM (
        SELECT
            id_agent_data,
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
        -- id_agent_data is in the key too: one Agent Domain identity can map to more than
        -- one legacy id_agent_data, and omitting it let two such rows collide on the same
        -- key, silently dropping one id_agent_data's row in the dedup below (AAREDE-526).
        XXHASH64(aer.uuid_person, settings.id_agent, aer.id_agent_data, settings.business_context, DATE(settings.ts_started)) AS id_agent_business_context,
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
        -- id_agent_data is stable; new.id_agent is not (null until Agent Domain resolves
        -- this person), so keying on it left orphaned duplicates (AAREDE-526).
        -- Hash the change-start timestamp, not DATE(), so two same-day switches
        -- cannot collide and get collapsed in the dedup below.
        XXHASH64(bc.uuid_person, bc.id_agent_data, bc.business_context, bc.ts_revision_started) AS id_agent_business_context,
        new.id_agent,
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
-- rows sharing a key can invert that window and erase coverage (AAREDE-526).
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
    FROM (
        SELECT
            id_agent_business_context,
            id_agent,
            id_agent_data,
            id_user,
            uuid_person,
            business_context,
            system_name,
            ts_revision_started,
            ROW_NUMBER() OVER (PARTITION BY id_agent_business_context ORDER BY system_name DESC) AS rn
        FROM (
            SELECT id_agent_business_context, id_agent, id_agent_data, id_user, uuid_person, business_context, system_name, ts_revision_started FROM new_business_contexts
            UNION
            SELECT id_agent_business_context, id_agent, id_agent_data, id_user, uuid_person, business_context, system_name, ts_revision_started FROM legacy_business_contexts
        )
    )
    WHERE rn = 1
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
    -- partitioned by id_agent_data (stable), not id_agent (null until Agent Domain resolves
    -- it). COALESCE to id_user so Agent Domain rows with null user.id_agent do not share
    -- one Spark NULL partition. -1 SECOND not -1 DAY so the end never lands before this
    -- row's own start when the next revision's time-of-day is earlier (AAREDE-526).
    LEAD(ts_revision_started) OVER (
        PARTITION BY COALESCE(CAST(id_agent_data AS STRING), CAST(id_user AS STRING))
        ORDER BY ts_revision_started
    ) - INTERVAL 1 SECOND AS ts_revision_ended
FROM
    business_contexts
