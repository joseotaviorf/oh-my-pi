WITH
hr_system_workers AS (
  SELECT
    id_person,
    work_relationships
  FROM
    datalake_hr_system_clean.workers
),
work_rel_step1 AS (
  SELECT
    id_person,
    EXPLODE (work_relationships) AS work_relationships
  FROM
    hr_system_workers
),
work_rel AS (
  SELECT
    id_person,
    work_relationships['PeriodOfServiceId'] AS id_period_of_service,
    work_relationships['assignments']       AS assignments
  FROM
    work_rel_step1
),
assignments_step1 AS (
  SELECT
    id_person,
    id_period_of_service,
    EXPLODE (assignments) AS assignments
  FROM
    work_rel
),
assignments AS (
  SELECT
    id_person,
    id_period_of_service,
    assignments['AssignmentId'] AS id_assignment,
    assignments['managers']     AS managers
  FROM
    assignments_step1
),
managers_step1 AS (
  SELECT
    id_person,
    id_period_of_service,
    id_assignment,
    EXPLODE (managers)   AS managers
  FROM
    assignments
)
SELECT DISTINCT
  -- ids
  managers['ManagerAssignmentId'] AS id_manager_assignment,
  id_assignment,
  -- non-ids
  id_person,
  id_period_of_service,
  managers['AssignmentSupervisorId'] AS id_assignment_supervisor,
  -- non-metrics
  managers['ManagerAssignmentNumber'] AS manager_assignment_number,
  managers['ManagerType'] AS manager_type,
  managers['CreatedBy'] AS created_by,
  managers['LastUpdatedBy'] AS last_updated_by,
  managers['ActionCode'] AS action_code,
  managers['ReasonCode'] AS reason_code,
  -- metrics
  -- dates
  DATE(managers['EffectiveStartDate']) AS dt_effective_start,
  DATE(managers['EffectiveEndDate']) AS dt_effective_end,
  -- timestamps
  TO_TIMESTAMP(
    SUBSTR(REPLACE(managers['CreationDate'], 'T', ' '), 0, 19),
    'yyyy-MM-dd HH:mm:ss'
  ) AS ts_created,
  TO_TIMESTAMP(
    SUBSTR(REPLACE(managers['LastUpdateDate'], 'T', ' '), 0, 19),
    'yyyy-MM-dd HH:mm:ss'
  ) AS ts_last_update,
  NOW() AS ts_load,
  -- partitions
  DATE_FORMAT(DATE(managers['EffectiveStartDate']), 'yyyy') AS YEAR,
  DATE_FORMAT(DATE(managers['EffectiveStartDate']), 'MM') AS MONTH
FROM
  managers_step1 managers
WHERE
  DATE_TRUNC('MONTH', DATE(managers['EffectiveStartDate'])) > DATE_TRUNC('MONTH', DATE('{load_start_date}'))