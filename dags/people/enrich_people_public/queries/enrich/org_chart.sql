WITH
emails_step1 AS (
  SELECT
    id_person,
    person_number,
    EXPLODE(emails) as emails
  FROM
    datalake_hr_system_clean.workers
  QUALIFY
    DENSE_RANK()
      OVER (ORDER BY dt_effective) = 2
),
emails_cte AS (
  SELECT
    id_person,
    emails['EmailAddress'] as email_address,
    emails['EmailType'] as email_type
  FROM
    emails_step1
  WHERE
    (emails['ToDate'] IS NULL OR emails['ToDate'] = '4712-12-31')
    AND emails['EmailType'] = 'W1'
  QUALIFY
    emails['LastUpdateDate'] = MAX(emails['LastUpdateDate'])
      OVER (PARTITION BY id_person, emails['EmailType'])
),
names_step1 AS (
  SELECT
    id_person,
    EXPLODE(names) names
  FROM
    datalake_hr_system_clean.workers
  QUALIFY
    dense_rank()
      OVER (ORDER BY dt_effective) = 2
),
names_cte AS (
  SELECT
    id_person,
    names["FullName"] AS full_name
  FROM
    names_step1
),
employee_cte AS (
  SELECT
    emails_cte.id_person,
    UPPER(names_cte.full_name) AS full_name,
    emails_cte.email_address AS work_email
  FROM
    emails_cte
  LEFT JOIN
    names_cte
      ON emails_cte.id_person = names_cte.id_person
),
manager_cte AS (
  SELECT DISTINCT
    id_period_of_service,
    id_assignment,
    id_person,
    id_manager_assignment
  FROM
    datalake_hr_system.managers
  WHERE
    dt_effective_start <= current_date
    AND manager_type = 'LINE_MANAGER'
  QUALIFY
    dt_effective_start = MAX(dt_effective_start)
    OVER (PARTITION BY id_assignment)
),
assignment_cte AS (
  SELECT DISTINCT
    assignments.id_person,
    assignments.id_assignment,
    assignments.assignment_number,
    assignments.assignment_name,
    assignments.business_unit_name,
    assignments.id_cost_center,
    assignments.cost_center_name,
    assignments.assignment_status_type,
    assignments.dt_effective_start,
    assignments.dt_effective_end,
    organizations.business,
    organizations.product,
    organizations.vertical,
    organizations.vice_presidency,
    organizations.directorate,
    organizations.subdirectorate,
    manager_cte.id_manager_assignment,
    manager_assignment.id_person AS id_manager_person,
    employee_manager.full_name AS manager_name,
    employee_manager.work_email AS manager_email
  FROM
    datalake_hr_system.assignments
  LEFT JOIN
    datalake_hr_system_clean.organizations
      ON organizations.id_organization = assignments.id_cost_center
  LEFT JOIN
    manager_cte
      ON manager_cte.id_assignment = assignments.id_assignment
  LEFT JOIN
    datalake_hr_system.assignments AS manager_assignment
      ON manager_assignment.id_assignment = manager_cte.id_manager_assignment
  LEFT JOIN
    employee_cte AS employee_manager
      ON employee_manager.id_person = manager_assignment.id_person
  WHERE
      assignments.dt_effective_start < current_date()
      AND assignments.assignment_type = 'E'
  QUALIFY
    assignments.dt_effective_start = MAX(assignments.dt_effective_start)
    OVER (PARTITION BY assignments.id_assignment)
)

SELECT
  assignment_cte.assignment_number,
  employee.full_name AS full_name,
  employee.work_email,
  assignment_cte.manager_name,
  assignment_cte.manager_email,
  UPPER(assignment_cte.assignment_name) AS assignment_name,
  assignment_cte.assignment_status_type,
  assignment_cte.business_unit_name,
  assignment_cte.cost_center_name,
  assignment_cte.business,
  assignment_cte.product,
  assignment_cte.vertical,
  assignment_cte.vice_presidency,
  assignment_cte.directorate,
  assignment_cte.subdirectorate,
  sheets.line,
  sheets.chapter,
  sheets.line_leader,
  sheets.team_leader,
  sheets.team_1 AS product_and_tech_team_1,
  sheets.team_2 AS product_and_tech_team_2,
  sheets.team_3 AS product_and_tech_team_3,
  sheets.team_4 AS product_and_tech_team_4,
  sheets.team_5 AS product_and_tech_team_5,
  sheets.team_6 AS product_and_tech_team_6,
  sheets.team_7 AS product_and_tech_team_7,
  sheets.team_8 AS product_and_tech_team_8,
  sheets.team_9 AS product_and_tech_team_9,
  sheets.team_10 AS product_and_tech_team_10,
  NOW() AS ts_load
FROM
  employee_cte AS employee
LEFT JOIN
  assignment_cte
    ON employee.id_person = assignment_cte.id_person
LEFT JOIN
  datalake_gsheets_clean.team_formation_product_tech sheets
    ON sheets.email = employee.work_email
