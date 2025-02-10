WITH
hr_system_workers AS (
  SELECT
    id_person,
    work_relationships,
    external_identifiers,
    dt_effective
  FROM
    datalake_hr_system_clean.workers
),
external_identifiers_step1 AS (
  SELECT
    id_person,
    EXPLODE (external_identifiers) external_identifiers
  FROM
    hr_system_workers
  QUALIFY dt_effective = MAX(dt_effective) OVER (PARTITION BY id_person)
),
external_identifiers AS (
  SELECT
    id_person
  FROM
    external_identifiers_step1
  WHERE
    external_identifiers['ExternalIdentifierType'] = 'ID_ONDA1'
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
  managers.id_person,
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
  NOW() AS ts_load
FROM
  managers_step1 AS managers
LEFT JOIN
  external_identifiers AS ei
    ON managers.id_person = ei.id_person
WHERE
  ei.id_person IS NULL
  AND (
    DATE(managers['EffectiveStartDate'])
      BETWEEN DATE_SUB(DATE('{load_start_date}'), 365) AND DATE('{load_end_date}')
    OR DATE(managers['LastUpdateDate'])
      BETWEEN DATE_SUB(DATE('{load_start_date}'), 365) AND DATE('{load_end_date}')
  )
