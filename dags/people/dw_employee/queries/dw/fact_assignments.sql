WITH
subordinates AS (
  SELECT
    mh.id_manager_period_of_service,
    SUM(IF(mh.is_direct_manager AND ed.assignment_status_type = 'ACTIVE', 1, 0)) AS qnt_directly_led,
    SUM(IF(NOT mh.is_direct_manager AND ed.assignment_status_type = 'ACTIVE', 1, 0)) AS qnt_undirectly_led
  FROM
    datalake_hr_system.management_hierarchy AS mh
  LEFT JOIN
    datalake_employment.employee_details AS ed
      ON ed.id_assignment = mh.id_assignment
  GROUP BY
    mh.id_manager_period_of_service
),
salaries AS (
  SELECT 
    s.id_assignment,
    s.currency_code,
    s.salary_amount,
    s.adjustment_amount,
    s.adjustment_percent,
    s.dt_started,
    s.dt_ended
  FROM 
    datalake_pin_compensation_clean.salary AS s
  WHERE 
    s.dt_started <= CURRENT_DATE
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY s.id_assignment ORDER BY s.dt_ended DESC) = 1
),
disability AS (
  SELECT DISTINCT
    sk_disability,
    id_person,
    has_self_declared_disability
  FROM 
    datalake_hr_system.disability
  QUALIFY
    ts_last_updated = MAX(ts_last_updated) OVER (PARTITION BY id_person)
),
current_assignments AS (
  SELECT 
    id_period_of_service, 
    id_job,
    id_organization,
    id_business_unit,
    legislation_code, 
    assignment_status_type,
    dt_projected_started,
    target_plr,
    career_track
  FROM 
    datalake_pin_core_clean.all_assignments
  WHERE
    (
      (
        dt_effective_started <= CURRENT_DATE
        AND assignment_type IN ('E', 'C')
      )
      OR (
        dt_projected_started > CURRENT_DATE
        AND assignment_type = 'P'
      )
    )
    AND dt_effective_ended >= CURRENT_DATE
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY id_period_of_service 
      ORDER BY dt_effective_ended ASC
    ) = 1
),
managers AS (
  SELECT
    id_period_of_service,
    id_manager_period_of_service,
    id_assignment,
    id_manager
  FROM
    datalake_pin.managers_history
  WHERE
    dt_effective_started <= CURRENT_DATE
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY assignment_number ORDER BY dt_effective_started DESC) = 1
),
active_jobs AS (
  SELECT
    id_job,
    id_grade_ladder
  FROM
    datalake_pin_core_clean.job
  WHERE
    dt_effective_ended = DATE('4712-12-31')
    AND is_active
),
active_valid_grades AS (
  SELECT
    id_job,
    id_grade
  FROM
    datalake_pin_core_clean.valid_grades 
  WHERE
    dt_effective_ended = DATE('4712-12-31')
),
salary_rates AS (
  SELECT
    id_rate,
    id_grade_ladder
  FROM
    datalake_pin_core_clean.rates
  WHERE
    dt_effective_ended = DATE('4712-12-31')
    AND rate_type = 'SALARY'
),
latest_rate_values AS (
  SELECT
    id_rate,
    id_rate_object,
    mid_value
  FROM 
    datalake_pin_core_clean.rate_values
  WHERE 
    dt_effective_ended = DATE('4712-12-31')
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY id_rate ORDER BY ts_updated DESC) = 1
),
job_salary_reference AS (
  SELECT DISTINCT
    j.id_job,
    rv.mid_value
  FROM
    active_jobs AS j
  INNER JOIN
    active_valid_grades AS vg
      ON j.id_job = vg.id_job
  INNER JOIN
    salary_rates AS sr
      ON j.id_grade_ladder = sr.id_grade_ladder
  INNER JOIN
    latest_rate_values AS rv
      ON sr.id_rate = rv.id_rate
      AND vg.id_grade = rv.id_rate_object
)

SELECT
  im.id_period_of_service AS sk_assignment,
  im.id_person AS sk_employee,
  COALESCE(da.sk_demographic_information, '-1') AS sk_demographic_information,
  COALESCE(d.sk_disability, '-1') AS sk_disability,
  COALESCE(a.id_organization, '-1') AS sk_cost_center,
  COALESCE(a.id_business_unit, '-1') AS sk_business_unit,
  COALESCE(a.id_job, '-1') AS sk_job,
  COALESCE(am.id_manager, '-1') AS sk_manager,
  COALESCE(am.id_manager_period_of_service, '-1') AS sk_manager_assignment,
  DATE_FORMAT(ps.dt_started, 'yyyyMMdd') AS sk_work_relationship_started_date,
  DATE_FORMAT(ps.dt_actual_termination, 'yyyyMMdd') AS sk_work_relationship_ended_date,
  DATE_FORMAT(s.dt_started, 'yyyyMMdd') AS sk_last_salary_increase_date,
  COALESCE(h.sk_hierarchy, '-1') AS sk_hierarchy,
  im.assignment_number,
  s.currency_code AS salary_currency_code,
  ROW_NUMBER() OVER (
    PARTITION BY im.id_person
    ORDER BY CASE WHEN ed.assignment_type <> 'P' THEN ps.dt_started ELSE NULL END DESC NULLS LAST
  ) = 1 AS is_last_valid_work_relationship,
  IF(ed.assignment_status_type = 'ACTIVE', TRUE, FALSE) AS is_active,
  IF(ed.assignment_type = 'P', TRUE, FALSE) AS is_pending_worker,
  CASE
    WHEN a.career_track = 'L'
      OR sub.qnt_directly_led > 0
    THEN TRUE
    ELSE FALSE
  END AS is_manager,
  COALESCE(d.has_self_declared_disability, FALSE) AS has_self_declared_disability,
  CASE 
    WHEN ed.assignment_type = 'P' THEN 0
    ELSE FLOOR(MONTHS_BETWEEN(COALESCE(ps.dt_actual_termination, CURRENT_DATE), ps.dt_started)) 
  END AS assignment_age_months,
  COALESCE(sub.qnt_directly_led, 0) AS qnt_directly_led,
  COALESCE(sub.qnt_undirectly_led, 0) AS qnt_undirectly_led,
  s.salary_amount AS salary,
  a.target_plr,
  COALESCE(jsr.mid_value, 0) AS salary_reference,
  s.adjustment_amount AS last_salary_increase,
  s.adjustment_percent AS pct_last_salary_increase,
  NOW() AS ts_load
FROM 
  datalake_employee_registration.identifier_mapping AS im
INNER JOIN 
  datalake_employment.employee_details AS ed
    ON ed.id_period_of_service = im.id_period_of_service
INNER JOIN 
  current_assignments AS a
    ON a.id_period_of_service = im.id_period_of_service
LEFT JOIN 
  datalake_pin_core_clean.periods_of_service AS ps
    ON ps.id_period_of_service = im.id_period_of_service
LEFT JOIN
  subordinates AS sub 
    ON sub.id_manager_period_of_service = im.id_period_of_service
LEFT JOIN
  salaries AS s
    ON s.id_assignment = im.id_assignment
LEFT JOIN
  disability AS d
    ON d.id_person = im.id_person
LEFT JOIN
  datalake_hr_system.demographic_attributes AS da
    ON da.id_person = im.id_person
    AND a.legislation_code = da.legislation_code
LEFT JOIN
  datalake_hr_system.hierarchy_ids AS h
    ON h.sk_assignment = im.id_period_of_service
LEFT JOIN 
  managers AS am 
    ON am.id_assignment = im.id_assignment
LEFT JOIN 
  job_salary_reference AS jsr 
    ON jsr.id_job = a.id_job