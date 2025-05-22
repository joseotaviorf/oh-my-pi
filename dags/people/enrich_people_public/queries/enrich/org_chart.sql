WITH 
manager_cte AS (
  SELECT
    id_period_of_service,
    id_assignment,
    id_person,
    id_manager_assignment
  FROM
    datalake_pin.managers_history
  WHERE
    dt_effective_started <= DATE(CURRENT_DATE)
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_assignment ORDER BY dt_effective_started DESC) = 1
),
assignment_cte AS (
  SELECT
    a.id_person,
    a.id_assignment,
    a.assignment_number,
    a.assignment_name,
    a.business_unit_name,
    a.id_cost_center,
    a.cost_center_name,
    a.assignment_status_type,
    a.dt_effective_start,
    a.dt_effective_end,
    o.business,
    o.product,
    o.vertical,
    o.vice_presidency,
    o.directorate,
    o.subdirectorate,
    m.id_manager_assignment,
    em.id_person AS id_manager_person,
    em.full_name AS manager_name,
    em.work_email AS manager_email,
    jf.name_job_family AS position_class
  FROM
    datalake_hr_system.assignments AS a
  LEFT JOIN
    datalake_hr_system_clean.organizations AS o
      ON o.id_organization = a.id_cost_center
  LEFT JOIN
    manager_cte AS m 
      ON m.id_assignment = a.id_assignment
  LEFT JOIN
    datalake_hr_system.employee_ids AS em
      ON em.id_assignment = m.id_manager_assignment
  LEFT JOIN 
    datalake_hr_system_clean.jobs AS j
      ON j.id_job = a.id_job
  LEFT JOIN
    datalake_hr_system_clean.job_families AS jf
      ON jf.id_job_family = j.id_job_family
  WHERE
    a.dt_effective_start < DATE(CURRENT_DATE)
    AND a.assignment_type IN ('E', 'C')
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY a.id_assignment ORDER BY a.dt_effective_start DESC) = 1
)

SELECT
  e.assignment_number,
  e.full_name AS full_name,
  e.work_email,
  a.manager_name,
  a.manager_email,
  UPPER(a.assignment_name) AS assignment_name,
  a.position_class AS job_class,
  a.assignment_status_type,
  a.business_unit_name,
  a.cost_center_name,
  a.business,
  a.product,
  a.vertical,
  a.vice_presidency,
  a.directorate,
  a.subdirectorate,
  s.line,
  s.chapter,
  s.line_leader,
  s.team_leader,
  s.team_1 AS product_and_tech_team_1,
  s.team_2 AS product_and_tech_team_2,
  s.team_3 AS product_and_tech_team_3,
  s.team_4 AS product_and_tech_team_4,
  s.team_5 AS product_and_tech_team_5,
  s.team_6 AS product_and_tech_team_6,
  s.team_7 AS product_and_tech_team_7,
  s.team_8 AS product_and_tech_team_8,
  s.team_9 AS product_and_tech_team_9,
  s.team_10 AS product_and_tech_team_10,
  NOW() AS ts_load
FROM
  datalake_hr_system.employee_ids AS e
INNER JOIN
  assignment_cte AS a
    ON e.id_assignment = a.id_assignment
LEFT JOIN
  datalake_gsheets_people_clean.team_formation_product_tech AS s
    ON s.assignment_number = e.assignment_number
