WITH
manager_ranked AS (
  SELECT
    id_period_of_service,
    id_assignment,
    id_person,
    id_manager_assignment,
    ROW_NUMBER() OVER (
      PARTITION BY id_assignment
      ORDER BY dt_effective_started DESC
    ) AS rn
  FROM
    datalake_pin.managers_history
  WHERE
    dt_effective_started <= DATE('{load_start_date}')
),
assignment_ranked AS (
  SELECT
    assignment_movement.id_person,
    assignment_movement.id_assignment,
    assignment_movement.assignment_number,
    assignment_movement.assignment_name,
    assignment_movement.business_unit_name,
    assignment_movement.id_cost_center,
    assignment_movement.cost_center_name,
    assignment_movement.assignment_status_type,
    assignment_movement.dt_effective_started,
    assignment_movement.dt_effective_ended,
    cost_center_org.business,
    cost_center_org.product,
    cost_center_org.vertical,
    cost_center_org.vice_presidency,
    cost_center_org.directorate,
    cost_center_org.subdirectorate,
    manager.id_manager_assignment,
    manager_identity.id_person AS id_manager_person,
    manager_identity.name AS manager_name,
    manager_identity.work_email AS manager_email,
    job_family.name_job_family AS position_class,
    ROW_NUMBER() OVER (
      PARTITION BY assignment_movement.id_assignment
      ORDER BY
        assignment_movement.dt_effective_started DESC,
        assignment_movement.dt_effective_ended DESC,
        assignment_movement.ts_load DESC
    ) AS rn
  FROM
    datalake_pin.movement_details AS assignment_movement
  LEFT JOIN
    datalake_hr_system_clean.organizations AS cost_center_org
      ON cost_center_org.id_organization = assignment_movement.id_cost_center
  LEFT JOIN
    manager_ranked AS manager
      ON manager.id_assignment = assignment_movement.id_assignment
      AND manager.rn = 1
  LEFT JOIN
    datalake_people.identifier_mapping AS manager_identity
      ON manager_identity.id_assignment = manager.id_manager_assignment
  LEFT JOIN
    datalake_hr_system_clean.jobs AS job
      ON job.id_job = assignment_movement.id_job
  LEFT JOIN
    datalake_hr_system_clean.job_families AS job_family
      ON job_family.id_job_family = job.id_job_family
  WHERE
    assignment_movement.dt_effective_started <= DATE('{load_start_date}')
    AND assignment_movement.assignment_type IN ('E', 'C')
)
SELECT
  employee.assignment_number,
  employee.name AS name,
  employee.work_email,
  assignment.manager_name,
  assignment.manager_email,
  UPPER(assignment.assignment_name) AS assignment_name,
  assignment.position_class AS job_class,
  assignment.assignment_status_type,
  assignment.business_unit_name,
  assignment.cost_center_name,
  assignment.business,
  assignment.product,
  assignment.vertical,
  assignment.vice_presidency,
  assignment.directorate,
  assignment.subdirectorate,
  product_tech_team.line,
  product_tech_team.chapter,
  product_tech_team.line_leader,
  product_tech_team.team_leader,
  product_tech_team.team_1 AS product_and_tech_team_1,
  product_tech_team.team_2 AS product_and_tech_team_2,
  product_tech_team.team_3 AS product_and_tech_team_3,
  product_tech_team.team_4 AS product_and_tech_team_4,
  product_tech_team.team_5 AS product_and_tech_team_5,
  product_tech_team.team_6 AS product_and_tech_team_6,
  product_tech_team.team_7 AS product_and_tech_team_7,
  product_tech_team.team_8 AS product_and_tech_team_8,
  product_tech_team.team_9 AS product_and_tech_team_9,
  product_tech_team.team_10 AS product_and_tech_team_10,
  IF(assignment.assignment_status_type = 'ACTIVE', TRUE, FALSE) AS is_active,
  employee.dt_started AS dt_hired,
  CASE
    WHEN employee.dt_actual_termination <= DATE('{load_start_date}') THEN employee.dt_actual_termination
    ELSE NULL
  END AS dt_terminated,
  NOW() AS ts_load
FROM
  datalake_people.identifier_mapping AS employee
INNER JOIN
  assignment_ranked AS assignment
    ON employee.id_assignment = assignment.id_assignment
LEFT JOIN
  datalake_gsheets_people_clean.team_formation_product_tech AS product_tech_team
    ON product_tech_team.assignment_number = employee.assignment_number
WHERE
  assignment.rn = 1
  AND assignment.assignment_status_type = 'ACTIVE'
