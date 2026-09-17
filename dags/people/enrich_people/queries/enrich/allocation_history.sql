-- SCD Type 2 history of Allocation Tool allocations, built from full snapshot
-- exports: one row per allocation per interval during which its tracked
-- attributes did not change. Point-in-time state is read with
-- `dt_reference BETWEEN dt_valid_from AND dt_valid_to`.
--
-- The source exports a complete snapshot every run, so consecutive exports
-- repeat states that did not change. A new interval is opened only when a
-- tracked attribute actually differs from the previous one -- otherwise the
-- history would carry one row per allocation per export, which is the per-day
-- snapshot this model exists to avoid.
--
-- Because snapshots are complete, an allocation missing from a later snapshot
-- no longer exists in the source: its last interval is closed the day before
-- that snapshot instead of being left open forever. Delta exports are partial,
-- so absence from a delta means nothing and only snapshots close intervals.
-- One row per person: identifier_mapping carries one row per assignment, and
-- is_person_latest_assignment is the flag it publishes for person-level views.
-- Resource Allocation 2.0 attaches each team-level group to a Line via
-- datalake_allocation_tool_clean.groups.line_name; NULL when the team has no Line in the export.
WITH group_lines AS (
    SELECT
        id_group,
        line_name
    FROM
        datalake_allocation_tool_clean.groups
),
current_assignments AS (
    SELECT
        person_number,
        id_person,
        name
    FROM
        datalake_people.identifier_mapping
    WHERE
        is_person_latest_assignment
        AND is_valid_assignment
        AND person_number IS NOT NULL
),
-- Employees are resolved by matching employee_name to identifier_mapping.name.
-- identifier_mapping.name already coalesces the social name, the display name
-- and the documented full name. Names that map to more than one person are
-- dropped rather than guessed.
employee_name_mapping AS (
    SELECT
        LOWER(TRIM(name)) AS normalized_name,
        MAX(person_number) AS person_number,
        MAX(id_person) AS id_person
    FROM
        current_assignments
    WHERE
        name IS NOT NULL
    GROUP BY
        LOWER(TRIM(name))
    HAVING
        COUNT(DISTINCT id_person) = 1
),
-- Several exports can carry the same allocation on the same day; only the last
-- state of a day is kept, so validity intervals never collapse to zero length.
daily_versions AS (
    SELECT
        allocations.id_allocation,
        allocations.id_employee,
        allocations.employee_name,
        allocations.id_group,
        allocations.id_tag,
        allocations.id_deactivated_by,
        groups.line_name,
        allocations.group_name,
        allocations.tag_name,
        allocations.chapter,
        allocations.vertical,
        allocations.team,
        allocations.status,
        allocations.is_active,
        allocations.ts_deactivated,
        allocations.is_leader,
        allocations.is_sample,
        allocations.ts_allocated,
        allocations.ts_created,
        allocations.ts_updated,
        allocations.ts_version,
        allocations.ts_export_generated,
        allocations.ts_file_modified,
        allocations.ts_load,
        TO_DATE(allocations.ts_version) AS dt_version,
        ROW_NUMBER() OVER (
            PARTITION BY
                allocations.id_allocation,
                TO_DATE(allocations.ts_version)
            ORDER BY
                allocations.ts_version DESC,
                allocations.ts_file_modified DESC
        ) AS rn_day
    FROM
        datalake_allocation_tool_clean.allocations AS allocations
    LEFT JOIN
        group_lines AS groups
            ON groups.id_group = allocations.id_group
),
-- Fingerprint of the attributes whose change starts a new interval. Deliberately
-- excluded: load provenance and ts_updated, which move on every export; and
-- id_employee, which the app reissues whenever it re-seeds employees from PIN --
-- on 2026-08-27 all 938 allocations got a new one while every other field stayed
-- byte-identical. Fingerprinting it would turn each re-seed into a fake state
-- change for the entire population.
fingerprinted_versions AS (
    SELECT
        id_allocation,
        id_employee,
        employee_name,
        id_group,
        id_tag,
        id_deactivated_by,
        line_name,
        group_name,
        tag_name,
        chapter,
        vertical,
        team,
        status,
        is_active,
        ts_deactivated,
        is_leader,
        is_sample,
        ts_allocated,
        ts_created,
        ts_updated,
        ts_version,
        ts_export_generated,
        ts_file_modified,
        ts_load,
        dt_version,
        MD5(
            CONCAT_WS(
                '||',
                COALESCE(id_group, ''),
                COALESCE(id_tag, ''),
                COALESCE(line_name, ''),
                COALESCE(group_name, ''),
                COALESCE(tag_name, ''),
                COALESCE(chapter, ''),
                COALESCE(vertical, ''),
                COALESCE(team, ''),
                COALESCE(status, ''),
                COALESCE(id_deactivated_by, ''),
                COALESCE(CAST(is_active AS STRING), ''),
                COALESCE(CAST(ts_deactivated AS STRING), ''),
                COALESCE(CAST(is_leader AS STRING), ''),
                COALESCE(CAST(is_sample AS STRING), '')
            )
        ) AS state_fingerprint
    FROM
        daily_versions
    WHERE
        rn_day = 1
),
state_changes AS (
    SELECT
        id_allocation,
        id_employee,
        employee_name,
        id_group,
        id_tag,
        id_deactivated_by,
        line_name,
        group_name,
        tag_name,
        chapter,
        vertical,
        team,
        status,
        is_active,
        ts_deactivated,
        is_leader,
        is_sample,
        ts_allocated,
        ts_created,
        ts_updated,
        ts_version,
        ts_export_generated,
        ts_file_modified,
        ts_load,
        dt_version,
        state_fingerprint,
        LAG(state_fingerprint) OVER (
            PARTITION BY id_allocation
            ORDER BY dt_version
        ) AS previous_fingerprint
    FROM
        fingerprinted_versions
),
-- Date of the first full snapshot taken after an allocation was last seen. When
-- one exists, the allocation was removed at the source.
last_seen_per_allocation AS (
    SELECT
        id_allocation,
        MAX(TO_DATE(ts_version)) AS dt_last_seen
    FROM
        datalake_allocation_tool_clean.allocations
    GROUP BY
        id_allocation
),
snapshot_days AS (
    SELECT DISTINCT
        TO_DATE(ts_version) AS dt_snapshot
    FROM
        datalake_allocation_tool_clean.allocations
    WHERE
        export_type = 'snapshot'
),
-- Interleave the two date streams and scan backwards instead of joining them on
-- an inequality: a range join has no hash key, so EMR can only plan it as a
-- nested loop. Scanning newest-first, the running minimum of the snapshot dates
-- seen so far IS the first snapshot after the current row. Ordering snapshot
-- rows after allocation rows within the same date keeps the comparison strict,
-- so the snapshot that last carried an allocation never counts as its removal.
removal_timeline AS (
    SELECT
        id_allocation,
        dt_last_seen AS dt_event,
        FALSE AS is_snapshot
    FROM
        last_seen_per_allocation
    UNION ALL
    SELECT
        CAST(NULL AS STRING) AS id_allocation,
        dt_snapshot AS dt_event,
        TRUE AS is_snapshot
    FROM
        snapshot_days
),
removal_scan AS (
    SELECT
        id_allocation,
        is_snapshot,
        MIN(
            CASE
                WHEN is_snapshot THEN dt_event
            END
        ) OVER (
            ORDER BY
                dt_event DESC,
                is_snapshot ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS dt_removed
    FROM
        removal_timeline
),
removal_dates AS (
    SELECT
        id_allocation,
        dt_removed
    FROM
        removal_scan
    WHERE
        NOT is_snapshot
        AND dt_removed IS NOT NULL
),
validity_intervals AS (
    SELECT
        id_allocation,
        id_employee,
        employee_name,
        id_group,
        id_tag,
        id_deactivated_by,
        line_name,
        group_name,
        tag_name,
        chapter,
        vertical,
        team,
        status,
        is_active,
        ts_deactivated,
        is_leader,
        is_sample,
        ts_allocated,
        ts_created,
        ts_updated,
        ts_version,
        ts_export_generated,
        ts_file_modified,
        ts_load,
        dt_version AS dt_valid_from,
        LEAD(dt_version) OVER (
            PARTITION BY id_allocation
            ORDER BY dt_version
        ) AS dt_next_change
    FROM
        state_changes
    WHERE
        previous_fingerprint IS NULL
        OR state_fingerprint <> previous_fingerprint
)
SELECT
    intervals.id_allocation,
    intervals.id_employee,
    name_mapping.id_person,
    name_mapping.person_number,
    intervals.id_group,
    intervals.id_tag,
    intervals.id_deactivated_by,
    intervals.line_name,
    intervals.group_name,
    intervals.tag_name,
    intervals.chapter,
    intervals.vertical,
    intervals.team,
    intervals.status,
    CASE
        WHEN LOWER(intervals.status) IN ('active', 'ativo') THEN 'active'
        ELSE 'inactive'
    END AS allocation_status,
    intervals.is_active,
    intervals.is_leader,
    intervals.is_sample,
    intervals.dt_valid_from,
    COALESCE(
        DATE_SUB(intervals.dt_next_change, 1),
        DATE_SUB(removals.dt_removed, 1),
        DATE('9999-12-31')
    ) AS dt_valid_to,
    intervals.dt_next_change IS NULL
        AND removals.dt_removed IS NULL AS is_current,
    removals.dt_removed IS NOT NULL
        AND intervals.dt_next_change IS NULL AS is_removed_at_source,
    intervals.ts_allocated,
    intervals.ts_created,
    intervals.ts_updated,
    intervals.ts_deactivated,
    intervals.ts_version,
    intervals.ts_export_generated,
    intervals.ts_file_modified,
    intervals.ts_load
FROM
    validity_intervals AS intervals
LEFT JOIN
    employee_name_mapping AS name_mapping
        ON name_mapping.normalized_name = LOWER(TRIM(intervals.employee_name))
LEFT JOIN
    removal_dates AS removals
        ON removals.id_allocation = intervals.id_allocation
