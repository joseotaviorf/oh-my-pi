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
        aer.id_agent,
        aer.id_user,
        aer.uuid_person,
        aud.business_context,
        aud.rev_type,
        aud.rev,
        -- Keep each context at an instant. For the same context, an ADD wins over
        -- a same-instant DEL so the transition remains observable (AAREDE-526).
        ROW_NUMBER() OVER (
            PARTITION BY aud.id_agent_data, aud.business_context, u.ts_revision
            ORDER BY aud.rev_type ASC, aud.rev DESC
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
-- Calculate context-specific intervals before removing DEL events. Otherwise a
-- deleted context remains open until the next unrelated context event.
legacy_context_events AS (
    SELECT
        id_agent_data,
        id_agent,
        id_user,
        uuid_person,
        business_context,
        rev_type,
        rev,
        ts_revision_started,
        LEAD(ts_revision_started) OVER (
            PARTITION BY id_agent_data, business_context
            ORDER BY ts_revision_started, rev_type ASC, rev DESC
        ) AS ts_context_ended
    FROM
        legacy_agent_data_business_contexts
    WHERE
        is_last_update_by_instant IS TRUE
),
legacy_agent_identity AS (
    SELECT
        id_agent_data,
        id_agent,
        id_user,
        uuid_person
    FROM (
        SELECT
            id_agent_data,
            id_agent,
            id_user,
            uuid_person,
            ROW_NUMBER() OVER (
                PARTITION BY id_agent_data
                ORDER BY ts_revision_started DESC, rev_type ASC, rev DESC
            ) AS rn_identity
        FROM
            legacy_context_events
    )
    WHERE
        rn_identity = 1
),
legacy_context_boundaries AS (
    SELECT
        id_agent_data,
        ts_revision_started AS ts_boundary
    FROM
        legacy_context_events
    UNION
    SELECT
        id_agent_data,
        ts_context_ended AS ts_boundary
    FROM
        legacy_context_events
    WHERE
        ts_context_ended IS NOT NULL
),
legacy_context_segments AS (
    SELECT
        id_agent_data,
        ts_boundary AS ts_revision_started,
        LEAD(ts_boundary) OVER (
            PARTITION BY id_agent_data
            ORDER BY ts_boundary
        ) AS ts_context_ended
    FROM
        legacy_context_boundaries
),
legacy_context_candidates AS (
    SELECT
        segments.id_agent_data,
        segments.ts_revision_started,
        segments.ts_context_ended,
        intervals.business_context,
        ROW_NUMBER() OVER (
            PARTITION BY segments.id_agent_data, segments.ts_revision_started
            ORDER BY
                intervals.ts_revision_started DESC,
                CASE
                    WHEN intervals.business_context = "SALE" THEN 1
                    WHEN intervals.business_context = "SALE_PRIMARY_MARKET" THEN 2
                    ELSE 3
                END,
                intervals.business_context DESC
        ) AS rn
    FROM
        legacy_context_segments AS segments
    INNER JOIN legacy_context_events AS intervals
        ON intervals.id_agent_data = segments.id_agent_data
        AND intervals.ts_revision_started <= segments.ts_revision_started
        AND intervals.rev_type <> 2
        AND (
            intervals.ts_context_ended IS NULL
            OR segments.ts_revision_started < intervals.ts_context_ended
        )
),
legacy_context_marked AS (
    SELECT
        candidates.id_agent_data,
        candidates.business_context,
        candidates.ts_revision_started,
        candidates.ts_context_ended,
        LAG(business_context) OVER (
            PARTITION BY id_agent_data
            ORDER BY ts_revision_started
        ) AS previous_business_context,
        LAG(ts_context_ended) OVER (
            PARTITION BY id_agent_data
            ORDER BY ts_revision_started
        ) AS previous_segment_ended
    FROM
        legacy_context_candidates AS candidates
    WHERE
        candidates.rn = 1
),
legacy_context_grouped AS (
    SELECT
        id_agent_data,
        business_context,
        ts_revision_started,
        ts_context_ended,
        SUM(
            CASE
                WHEN previous_business_context = business_context
                    AND previous_segment_ended = ts_revision_started
                    THEN 0
                ELSE 1
            END
        ) OVER (
            PARTITION BY id_agent_data
            ORDER BY ts_revision_started
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS context_group
    FROM
        legacy_context_marked
),
legacy_context_intervals AS (
    SELECT
        grouped.id_agent_data,
        identity.id_agent,
        identity.id_user,
        identity.uuid_person,
        grouped.business_context,
        MIN(grouped.ts_revision_started) AS ts_revision_started,
        CASE
            WHEN COUNT(grouped.ts_context_ended) < COUNT(*)
                THEN CAST(NULL AS TIMESTAMP)
            ELSE MAX(grouped.ts_context_ended)
        END AS ts_context_ended
    FROM
        legacy_context_grouped AS grouped
    INNER JOIN legacy_agent_identity AS identity
        ON identity.id_agent_data = grouped.id_agent_data
    GROUP BY
        grouped.id_agent_data,
        identity.id_agent,
        identity.id_user,
        identity.uuid_person,
        grouped.business_context,
        grouped.context_group
),
new_business_context_events AS (
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
        settings.ts_started AS ts_revision_started,
        ROW_NUMBER() OVER (
            PARTITION BY
                COALESCE(
                    CAST(aer.id_agent_data AS STRING),
                    CAST(aer.id_user AS STRING),
                    CAST(settings.id_agent AS STRING)
                ),
                settings.ts_started
            ORDER BY
                CASE
                    WHEN settings.business_context = "SALE" THEN 1
                    WHEN settings.business_context = "SALE_PRIMARY_MARKET" THEN 2
                    ELSE 3
                END,
                settings.business_context DESC
        ) AS rn_same_instant
    FROM
        agent_external_reference AS aer
    JOIN
        datalake_ebdb_agent_events.capability_settings AS settings
            ON settings.id_agent = aer.id_agent
    WHERE
        settings.is_last_update_by_date IS TRUE
),
new_business_contexts AS (
    SELECT
        id_agent_business_context,
        id_agent,
        id_agent_data,
        id_user,
        uuid_person,
        business_context,
        system_name,
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(
                CAST(id_agent_data AS STRING),
                CAST(id_user AS STRING),
                CAST(id_agent AS STRING)
            )
            ORDER BY ts_revision_started
        ) = 1 AS is_first_event,
        ts_revision_started,
        CAST(NULL AS TIMESTAMP) AS ts_context_ended
    FROM
        new_business_context_events
    WHERE
        rn_same_instant = 1
),
legacy_business_contexts AS (
    SELECT
        -- id_agent_data is stable; new.id_agent is not (null until Agent Domain resolves
        -- this person), so keying on it left orphaned duplicates (AAREDE-526).
        -- Hash the change-start timestamp, not DATE(), so two same-day switches
        -- cannot collide and get collapsed in the dedup below.
        XXHASH64(bc.uuid_person, bc.id_agent_data, bc.business_context, bc.ts_revision_started) AS id_agent_business_context,
        COALESCE(new.id_agent, bc.id_agent) AS id_agent,
        bc.id_agent_data,
        bc.id_user,
        bc.uuid_person,
        bc.business_context,
        "LEGACY_SYSTEM" AS system_name,
        bc.ts_revision_started,
        CASE
            WHEN new.ts_revision_started IS NOT NULL
                AND (
                    bc.ts_context_ended IS NULL
                    OR new.ts_revision_started < bc.ts_context_ended
                )
                THEN new.ts_revision_started
            ELSE bc.ts_context_ended
        END AS ts_context_ended
    FROM
        legacy_context_intervals AS bc
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
        ts_revision_started,
        ts_context_ended
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
            ts_context_ended,
            ROW_NUMBER() OVER (PARTITION BY id_agent_business_context ORDER BY system_name DESC) AS rn
        FROM (
            SELECT id_agent_business_context, id_agent, id_agent_data, id_user, uuid_person, business_context, system_name, ts_revision_started, ts_context_ended FROM new_business_contexts
            UNION
            SELECT id_agent_business_context, id_agent, id_agent_data, id_user, uuid_person, business_context, system_name, ts_revision_started, ts_context_ended FROM legacy_business_contexts
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
    CASE
        WHEN system_name = "LEGACY_SYSTEM"
            THEN ts_context_ended - INTERVAL 1 SECOND
        ELSE LEAD(ts_revision_started) OVER (
            PARTITION BY COALESCE(
                CAST(id_agent_data AS STRING),
                CAST(id_user AS STRING)
            )
            ORDER BY ts_revision_started
        ) - INTERVAL 1 SECOND
    END AS ts_revision_ended
FROM
    business_contexts
