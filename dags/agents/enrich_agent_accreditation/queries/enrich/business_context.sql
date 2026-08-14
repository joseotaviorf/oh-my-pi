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
-- NOTE: considered replacing this ad hoc resolution with datalake_agent.agent_unified_identity
-- (which has a proper deterministic tiebreak per id_agent_data, is_agent_data_replace_key) --
-- but that table only covers ~6.4k of the ~51k agents in business_context (it only accumulates
-- identities touched since its own DAG's 2024-01-01 start, not a full historical backfill), so
-- swapping it in drops coverage for the vast majority of legacy agents. Not usable as a direct
-- substitute without first backfilling agent_unified_identity itself -- out of scope here.
-- The duplicate-row symptom this CTE can produce is instead guarded downstream, right before
-- the ts_revision_ended LEAD() that it corrupts (see the business_contexts CTE below).
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
        -- each real transition writes a same-instant pair: the closed value (rev_type=2/DEL)
        -- and the new value (rev_type=0/ADD). Ties on ts_revision need a deterministic
        -- tiebreaker or Trino/Spark can pick either row, non-deterministically flipping which
        -- context "wins" that day (AAREDE-526) -- rev_type ASC prefers ADD (0) over DEL (2).
        ROW_NUMBER() OVER(PARTITION BY aud.id_agent_data, DATE(u.ts_revision) ORDER BY u.ts_revision DESC, aud.rev_type ASC) = 1 AS is_last_update_by_date,
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
        -- keyed on id_agent_data (stable, native to the legacy row), not new.id_agent:
        -- new.id_agent depends on whether Agent Domain has resolved a first event for this
        -- person yet, which changes across incremental runs as Agent Domain data arrives.
        -- Keying on it made the merge key unstable and left orphaned stale-dated duplicate
        -- rows once Agent Domain caught up (AAREDE-526).
        XXHASH64(bc.uuid_person, bc.id_agent_data, bc.business_context, DATE(bc.ts_revision_started)) AS id_agent_business_context,
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
business_contexts_raw AS (
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
),
-- agent_external_reference can legitimately emit more than one row per (uuid_person,
-- id_agent_data) when a person has multiple id_user accounts mapped to the same
-- id_agent_data. Those rows differ only in id_user, so UNION (which dedupes on full-row
-- equality) does not collapse them, and two rows for the same id_agent_data can end up
-- sharing the identical ts_revision_started. The LEAD() below has no tiebreaker for ties,
-- so it can pick a tied row's own timestamp as "the next one," producing a
-- ts_revision_ended before its own ts_revision_started -- a degenerate, permanently-closed
-- interval that silently erases coverage (AAREDE-526). Collapsing to one row per the real
-- merge key here, before LEAD() ever sees the data, prevents that.
business_contexts AS (
    SELECT
        id_agent_business_context, id_agent, id_agent_data, id_user, uuid_person,
        business_context, system_name, ts_revision_started
    FROM (
        SELECT *,
            ROW_NUMBER() OVER (PARTITION BY id_agent_business_context ORDER BY system_name DESC) AS rn
        FROM business_contexts_raw
    ) t
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
    -- partitioned by id_agent_data (stable across both branches), not id_agent: id_agent is
    -- null for legacy rows until Agent Domain resolves a first event for the person, which
    -- silently split one continuous per-agent timeline into two partitions and broke interval
    -- closure once Agent Domain data arrived (AAREDE-526).
    -- subtracting a flat 1 DAY (not 1 second) meant that whenever the next revision's
    -- time-of-day was earlier than this row's own time-of-day, the computed end could land
    -- before this row's own start -- an inverted, unsatisfiable interval that silently erased
    -- coverage for that agent even though the two revisions were on consecutive calendar
    -- days, not the same one (AAREDE-526). 1 SECOND guarantees the end is always strictly
    -- before the next start and never before this row's own start.
    LEAD(ts_revision_started) OVER (PARTITION BY id_agent_data ORDER BY ts_revision_started) - INTERVAL 1 SECOND AS ts_revision_ended
FROM
    business_contexts