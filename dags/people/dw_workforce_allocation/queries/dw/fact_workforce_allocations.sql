-- SCD Type 2 workforce allocation fact.
--
-- Grain: one row per allocation per interval over which its FTE share is
-- constant. An active allocation's share is 1/N, where N is the number of active
-- tags the employee holds in that group -- and N changes whenever ANOTHER tag in
-- the same group starts or ends. So the employee/group timeline is cut at every
-- such boundary and each active allocation is split along those cuts, which keeps
-- allocation_fte constant within a row without materializing a per-day snapshot.
-- Inactive allocations carry FTE 0 and pass through with their original interval.
--
-- Sample records are application-generated test data and are filtered once, so
-- they never reach the fact nor the FTE denominator.
WITH production_allocations AS (
    SELECT
        id_person,
        person_number,
        id_employee,
        id_allocation,
        id_group,
        id_tag,
        group_name,
        tag_name,
        chapter,
        vertical,
        team,
        status,
        allocation_status,
        is_leader,
        dt_valid_from,
        dt_valid_to,
        ts_allocated,
        ts_created,
        ts_updated,
        ts_version,
        ts_export_generated,
        ts_file_modified,
        ts_load
    FROM
        datalake_people.allocation_history
    WHERE
        NOT COALESCE(is_sample, FALSE)
),
active_allocations AS (
    SELECT
        id_employee,
        id_group,
        id_tag,
        dt_valid_from,
        dt_valid_to
    FROM
        production_allocations
    WHERE
        allocation_status = 'active'
        AND id_tag IS NOT NULL
),
-- Every date on which the set of active tags of an employee/group can change.
denominator_boundaries AS (
    SELECT
        id_employee,
        id_group,
        dt_valid_from AS dt_boundary
    FROM
        active_allocations
    UNION
    SELECT
        id_employee,
        id_group,
        DATE_ADD(dt_valid_to, 1) AS dt_boundary
    FROM
        active_allocations
    WHERE
        dt_valid_to < DATE('9999-12-31')
),
denominator_intervals AS (
    SELECT
        id_employee,
        id_group,
        dt_boundary AS dt_interval_start,
        COALESCE(
            DATE_SUB(
                LEAD(dt_boundary) OVER (
                    PARTITION BY id_employee, id_group
                    ORDER BY dt_boundary
                ),
                1
            ),
            DATE('9999-12-31')
        ) AS dt_interval_end
    FROM
        denominator_boundaries
),
-- Within a boundary interval the set of active tags is constant by construction,
-- so a plain count gives the equal-share denominator.
active_tag_counts AS (
    SELECT
        intervals.id_employee,
        intervals.id_group,
        intervals.dt_interval_start,
        intervals.dt_interval_end,
        COUNT(DISTINCT allocations.id_tag) AS tag_count
    FROM
        denominator_intervals AS intervals
    JOIN
        active_allocations AS allocations
            ON allocations.id_employee = intervals.id_employee
            AND allocations.id_group = intervals.id_group
            AND allocations.dt_valid_from <= intervals.dt_interval_start
            AND allocations.dt_valid_to >= intervals.dt_interval_end
    GROUP BY
        intervals.id_employee,
        intervals.id_group,
        intervals.dt_interval_start,
        intervals.dt_interval_end
),
active_fact AS (
    SELECT
        snapshots.id_person,
        snapshots.person_number,
        snapshots.id_employee,
        snapshots.id_allocation,
        snapshots.id_group,
        snapshots.id_tag,
        snapshots.group_name,
        snapshots.tag_name,
        snapshots.chapter,
        snapshots.vertical,
        snapshots.team,
        snapshots.status,
        snapshots.allocation_status,
        snapshots.is_leader,
        GREATEST(snapshots.dt_valid_from, counts.dt_interval_start) AS dt_valid_from,
        LEAST(snapshots.dt_valid_to, counts.dt_interval_end) AS dt_valid_to,
        CAST(1.0 / counts.tag_count AS DECIMAL(18, 8)) AS allocation_fte,
        snapshots.ts_allocated,
        snapshots.ts_created,
        snapshots.ts_updated,
        snapshots.ts_version,
        snapshots.ts_export_generated,
        snapshots.ts_file_modified,
        snapshots.ts_load
    FROM
        production_allocations AS snapshots
    JOIN
        active_tag_counts AS counts
            ON counts.id_employee = snapshots.id_employee
            AND counts.id_group = snapshots.id_group
            AND counts.dt_interval_start <= snapshots.dt_valid_to
            AND counts.dt_interval_end >= snapshots.dt_valid_from
    WHERE
        snapshots.allocation_status = 'active'
        AND snapshots.id_tag IS NOT NULL
),
inactive_fact AS (
    SELECT
        id_person,
        person_number,
        id_employee,
        id_allocation,
        id_group,
        id_tag,
        group_name,
        tag_name,
        chapter,
        vertical,
        team,
        status,
        allocation_status,
        is_leader,
        dt_valid_from,
        dt_valid_to,
        CAST(0.0 AS DECIMAL(18, 8)) AS allocation_fte,
        ts_allocated,
        ts_created,
        ts_updated,
        ts_version,
        ts_export_generated,
        ts_file_modified,
        ts_load
    FROM
        production_allocations
    WHERE
        allocation_status <> 'active'
        OR id_tag IS NULL
),
fact_rows AS (
    SELECT
        id_person,
        person_number,
        id_employee,
        id_allocation,
        id_group,
        id_tag,
        group_name,
        tag_name,
        chapter,
        vertical,
        team,
        status,
        allocation_status,
        is_leader,
        dt_valid_from,
        dt_valid_to,
        allocation_fte,
        ts_allocated,
        ts_created,
        ts_updated,
        ts_version,
        ts_export_generated,
        ts_file_modified,
        ts_load
    FROM
        active_fact
    UNION ALL
    SELECT
        id_person,
        person_number,
        id_employee,
        id_allocation,
        id_group,
        id_tag,
        group_name,
        tag_name,
        chapter,
        vertical,
        team,
        status,
        allocation_status,
        is_leader,
        dt_valid_from,
        dt_valid_to,
        allocation_fte,
        ts_allocated,
        ts_created,
        ts_updated,
        ts_version,
        ts_export_generated,
        ts_file_modified,
        ts_load
    FROM
        inactive_fact
)
SELECT
    COALESCE(id_person, -1) AS sk_employee,
    DATE_FORMAT(dt_valid_from, 'yyyyMMdd') AS sk_valid_from_date,
    person_number,
    id_employee,
    id_allocation,
    id_group,
    id_tag,
    group_name,
    tag_name,
    chapter,
    vertical,
    team,
    status,
    allocation_status,
    allocation_fte,
    CASE
        WHEN allocation_status = 'active' THEN TRUE
        ELSE FALSE
    END AS is_active,
    is_leader,
    dt_valid_from,
    dt_valid_to,
    dt_valid_to = DATE('9999-12-31') AS is_current,
    ts_allocated,
    ts_created,
    ts_updated,
    ts_version,
    ts_export_generated,
    ts_file_modified,
    ts_load
FROM
    fact_rows
