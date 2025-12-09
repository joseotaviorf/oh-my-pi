-- Base assignments: Filter primary E/C assignments and all P (pending) assignments
-- Grain: One row per assignment effective period
WITH
assignment_base AS (
  SELECT
    aa.id_assignment,
    aa.id_period_of_service,
    aa.id_person,
    aa.assignment_number,
    aa.legislation_code,
    aa.assignment_type,
    aa.assignment_status_type,
    aa.action_code,
    aa.reason_code,
    aa.dt_effective_started,
    aa.dt_effective_ended,
    aa.dt_projected_started
  FROM
    datalake_pin_core_clean.all_assignments AS aa
  WHERE
    aa.assignment_type IN ('E', 'C', 'P')
    AND (
      (aa.is_primary AND aa.assignment_type IN ('E', 'C'))
      OR (aa.assignment_type = 'P')
    )
    AND aa.dt_effective_started <= CURRENT_DATE()
),
-- Get latest union name per period of service from legacy HR system
-- Note: Union data not yet available in PIN tables
union_info AS (
  SELECT 
    wr.PeriodOfServiceId AS id_period_of_service,
    a.UnionName AS union_name,
    TO_DATE(w.dt_effective, 'yyyyMMdd') AS dt_effective
  FROM
    datalake_hr_system_clean.workers AS w
  LATERAL VIEW OUTER
    EXPLODE(w.work_relationships) AS wr
  LATERAL VIEW OUTER
    EXPLODE(wr.assignments) AS a
  WHERE
    TO_DATE(w.dt_effective, 'yyyyMMdd') <= CURRENT_DATE()
    AND a.UnionName IS NOT NULL
),
-- Get dismissal type and reason for terminated assignments
-- Only captures the first termination event per period of service
dismissal_info AS (
  SELECT
    aa.id_period_of_service,
    al.description AS dismissal_type,
    art.action_reason AS dismissal_reason
  FROM
    datalake_pin_core_clean.all_assignments AS aa
  LEFT JOIN
    datalake_hr_system_clean.actions_lov AS al
      ON al.action_code = aa.action_code
  LEFT JOIN
    datalake_pin_core_clean.action_reason_base AS arb
      ON arb.action_reason_code = aa.reason_code
  LEFT JOIN
    datalake_pin_core_clean.action_reason_translation AS art
      ON art.id_action_reason = arb.id_action_reason
      AND art.language = 'PTB'
  WHERE
    aa.is_primary
    AND aa.assignment_type IN ('E', 'C', 'P')
    AND aa.action_code IN (
      'TERMINATION', 'RESIGNATION', 'DEATH', 'GLB_TRANSFER', 'EXPATRIADO'
    )
    AND aa.assignment_status_type = 'INACTIVE'
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY aa.id_period_of_service
      ORDER BY aa.dt_effective_ended ASC
    ) = 1
),
-- Get period of service dates (contract start and termination dates)
period_of_service_info AS (
  SELECT
    id_period_of_service,
    dt_started,
    dt_actual_termination,
    dt_notified_termination
  FROM
    datalake_pin_core_clean.periods_of_service
),
-- Get person_number for business key
person_info AS (
  SELECT
    id_person,
    person_number
  FROM
    datalake_pin_core_clean.all_people
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY id_person
      ORDER BY dt_effective_started DESC
    ) = 1
),
-- Join all enrichment data to base assignments
-- Combines legacy registration, union, dismissal info, and POS dates
assignment_with_enrichment AS (
  SELECT
    ab.id_assignment,
    ab.id_person,
    ab.assignment_number,
    pi.person_number,
    COALESCE(im.legacy_registration, '-1') AS legacy_registration,
    ab.legislation_code,
    ab.assignment_type AS worker_type,
    ab.assignment_status_type,
    COALESCE(ui.union_name, '-1') AS union_name,
    COALESCE(di.dismissal_type, '-1') AS dismissal_type,
    COALESCE(di.dismissal_reason, '-1') AS dismissal_reason,
    ab.dt_projected_started,
    pos.dt_started,
    pos.dt_actual_termination,
    pos.dt_notified_termination,
    ab.dt_effective_started
  FROM
    assignment_base AS ab
  LEFT JOIN
    person_info AS pi
      ON ab.id_person = pi.id_person
  LEFT JOIN
    datalake_employee_registration.identifier_mapping AS im
      ON ab.id_period_of_service = im.id_period_of_service
  LEFT JOIN
    union_info AS ui
      ON ab.id_period_of_service = ui.id_period_of_service
  LEFT JOIN
    dismissal_info AS di
      ON ab.id_period_of_service = di.id_period_of_service
  LEFT JOIN
    period_of_service_info AS pos
      ON ab.id_period_of_service = pos.id_period_of_service
),
-- Detect attribute changes to create SCD Type 2 versions
-- Marks rows where any tracked attribute differs from the previous record
assignment_changes AS (
  SELECT
    *,
    CASE
      WHEN LAG(worker_type) OVER (
        PARTITION BY id_assignment
        ORDER BY dt_effective_started
      ) <> worker_type
        OR LAG(assignment_status_type) OVER (
          PARTITION BY id_assignment 
          ORDER BY dt_effective_started
        ) <> assignment_status_type
        OR LAG(union_name) OVER (
          PARTITION BY id_assignment 
          ORDER BY dt_effective_started
        ) <> union_name
        OR LAG(dismissal_type) OVER (
          PARTITION BY id_assignment 
          ORDER BY dt_effective_started
        ) <> dismissal_type
        OR LAG(dismissal_reason) OVER (
          PARTITION BY id_assignment 
          ORDER BY dt_effective_started
        ) <> dismissal_reason
        OR COALESCE(
          LAG(dt_projected_started) OVER (
            PARTITION BY id_assignment 
            ORDER BY dt_effective_started
          ),
          DATE('1900-01-01')
        ) <> COALESCE(dt_projected_started, DATE('1900-01-01'))
        OR COALESCE(
          LAG(dt_started) OVER (
            PARTITION BY id_assignment 
            ORDER BY dt_effective_started
          ),
          DATE('1900-01-01')
        ) <> COALESCE(dt_started, DATE('1900-01-01'))
        OR COALESCE(
          LAG(dt_actual_termination) OVER (
            PARTITION BY id_assignment 
            ORDER BY dt_effective_started
          ),
          DATE('1900-01-01')
        ) <> COALESCE(dt_actual_termination, DATE('1900-01-01'))
        OR COALESCE(
          LAG(dt_notified_termination) OVER (
            PARTITION BY id_assignment 
            ORDER BY dt_effective_started
          ),
          DATE('1900-01-01')
        ) <> COALESCE(dt_notified_termination, DATE('1900-01-01'))
        OR LAG(worker_type) OVER (
          PARTITION BY id_assignment 
          ORDER BY dt_effective_started
        ) IS NULL
      THEN 1
      ELSE 0
    END AS is_change
  FROM
    assignment_with_enrichment
),
-- Create change groups using cumulative sum of is_change flag
-- This groups consecutive periods with identical attributes into the same change_group
assignment_groups AS (
  SELECT
    *,
    SUM(is_change) OVER (
      PARTITION BY id_assignment
      ORDER BY dt_effective_started
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS change_group
  FROM
    assignment_changes
),
-- Consolidate consecutive periods with identical attributes into single SCD Type 2 versions
-- Groups by change_group and collapses to earliest dt_effective_started as dt_valid_from
consolidated_assignments AS (
  SELECT
    id_assignment,
    id_person,
    change_group,
    assignment_number,
    person_number,
    legacy_registration,
    legislation_code,
    worker_type,
    assignment_status_type,
    union_name,
    dismissal_type,
    dismissal_reason,
    dt_projected_started,
    dt_started,
    dt_actual_termination,
    dt_notified_termination,
    MIN(dt_effective_started) AS dt_valid_from
  FROM
    assignment_groups
  GROUP BY
    id_assignment,
    id_person,
    change_group,
    assignment_number,
    person_number,
    legacy_registration,
    legislation_code,
    worker_type,
    assignment_status_type,
    union_name,
    dismissal_type,
    dismissal_reason,
    dt_projected_started,
    dt_started,
    dt_actual_termination,
    dt_notified_termination
)
-- Final SELECT: Calculate SCD Type 2 attributes (version, dt_valid_to, is_current)
-- is_current logic: Only one current assignment per person, prioritizing E > C > P
SELECT
  MD5(CONCAT_WS('|', CAST(ca.id_assignment AS STRING), CAST(ca.dt_valid_from AS STRING))) AS sk_assignment_version,
  ca.assignment_number,
  ca.person_number,
  ca.legacy_registration,
  ca.legislation_code,
  ca.worker_type,
  ca.assignment_status_type,
  ca.union_name,
  ca.dismissal_type,
  ca.dismissal_reason,
  ca.dt_projected_started,
  ca.dt_started,
  ca.dt_actual_termination AS dt_termination,
  ca.dt_notified_termination,
  ROW_NUMBER() OVER (
    PARTITION BY ca.id_assignment
    ORDER BY ca.dt_valid_from
  ) AS version,
  ca.dt_valid_from,
  COALESCE(
    LEAD(ca.dt_valid_from) OVER (
      PARTITION BY ca.id_assignment
      ORDER BY ca.dt_valid_from
    ) - INTERVAL '1 DAY',
    DATE('9999-12-31')
  ) AS dt_valid_to,
  (
    LEAD(ca.dt_valid_from) OVER (
      PARTITION BY ca.id_assignment
      ORDER BY ca.dt_valid_from
    ) IS NULL
    AND ROW_NUMBER() OVER (
      PARTITION BY ca.id_person
      ORDER BY
        CASE
          WHEN LEAD(ca.dt_valid_from) OVER (
            PARTITION BY ca.id_assignment
            ORDER BY ca.dt_valid_from
          ) IS NULL
          THEN 1
          ELSE 0
        END DESC,
        CASE ca.worker_type
          WHEN 'E' THEN 1
          WHEN 'C' THEN 2
          WHEN 'P' THEN 3
          ELSE 4
        END ASC,
        ca.dt_valid_from DESC
    ) = 1
  ) AS is_current,
  NOW() AS ts_load
FROM
  consolidated_assignments AS ca
