WITH assignment AS (
  SELECT DISTINCT 
    a.id_period_of_service,
    a.id_assignment,
    a.assignment_number,
    a.id_person,
    a.id_business_unit,
    a.id_cost_center,
    a.id_job,
    a.id_cost_center,
    a.career_track,
    a.target_plr,
    COALESCE(
      a.band,
      LAG(a.band) OVER (
        PARTITION BY a.id_assignment
        ORDER BY
          a.dt_effective_start
      ),
      1
    ) AS band,
    a.action_code,
    a.dt_effective_start,
    a.assignment_status_type,
    a.dt_projected_start,
    a.year,
    a.month
  FROM
    datalake_hr_system.assignments AS a
  ORDER BY
    dt_effective_start
),
assignments_present AS (
  SELECT
    a.id_period_of_service,
    a.id_assignment,
    a.assignment_number,
    a.id_person,
    a.id_business_unit,
    a.id_cost_center,
    a.id_job,
    a.career_track,
    a.target_plr,
    SUM(
      CASE
        WHEN action_code = 'PROMOTION'
        OR band != LAG(band) OVER (
          PARTITION BY id_assignment
          ORDER BY
            dt_effective_start
        ) THEN 1
        ELSE 0
      END
    ) over (
      PARTITION BY id_assignment
      ORDER BY
        dt_effective_start
    ) AS qnt_promotions,
    a.dt_effective_start,
    a.dt_projected_start,
    a.assignment_status_type,
    a.year,
    a.month
  FROM
    assignment a
  WHERE
    a.dt_effective_start <= DATE('{load_start_date}') 
  QUALIFY dt_effective_start = MAX(dt_effective_start) over (PARTITION BY a.id_assignment)
),
assignments_future AS (
  SELECT
    a.id_period_of_service,
    a.id_assignment,
    a.assignment_number,
    a.id_person,
    a.id_business_unit,
    a.id_cost_center,
    a.id_job,
    a.career_track,
    a.target_plr,
    SUM(
      CASE
        WHEN action_code = 'PROMOTION'
        OR band != LAG(band) OVER (
          PARTITION BY id_assignment
          ORDER BY
            dt_effective_start
        ) THEN 1
        ELSE 0
      END
    ) over (
      PARTITION BY id_assignment
      ORDER BY
        dt_effective_start
    ) AS qnt_promotions,
    a.dt_effective_start,
    a.dt_projected_start,
    a.assignment_status_type,
    a.year,
    a.month
  FROM
    assignment a
  WHERE
    a.dt_effective_start > DATE('{load_start_date}') 
  QUALIFY dt_effective_start = MAX(dt_effective_start) over (PARTITION BY a.id_assignment)
),
managers_present AS (
  SELECT
    DISTINCT id_period_of_service,
    id_assignment,
    id_manager_assignment
  FROM
    datalake_hr_system.managers
  WHERE
    dt_effective_start <= DATE('{load_start_date}')
    AND manager_type = 'LINE_MANAGER' 
  QUALIFY dt_effective_start = MAX(dt_effective_start) over (PARTITION BY id_assignment)
),
managers_future AS (
  SELECT
    DISTINCT id_period_of_service,
    id_assignment,
    id_manager_assignment
  FROM
    datalake_hr_system.managers
  WHERE
    dt_effective_start > DATE('{load_start_date}')
    AND manager_type = 'LINE_MANAGER' 
  QUALIFY dt_effective_start = MAX(dt_effective_start) over (PARTITION BY id_assignment)
),
hr_system_workers AS (
  SELECT
    id_person,
    work_relationships,
    external_identifiers
  FROM
    datalake_hr_system_clean.workers
  WHERE
    dt_effective = REPLACE('{load_start_date}', '-', '')
),
external_identifiers_step1 AS (
  SELECT
    id_person,
    explode(external_identifiers) external_identifiers
  FROM
    hr_system_workers
),
external_identifiers AS (
  SELECT
    id_person
  FROM
    external_identifiers_step1
  WHERE
    external_identifiers ['ExternalIdentifierType'] = 'ID_ONDA1'
),
work_rel_step1 AS(
  SELECT
    id_person,
    explode(work_relationships) as work_relationships
  FROM
    hr_system_workers
),
work_rel AS (
  SELECT
    id_person,
    work_relationships ['PeriodOfServiceId'] AS id_period_service,
    work_relationships ['assignments'] AS assignments
  FROM
    work_rel_step1
),
assignments_step1 AS (
  SELECT
    id_person,
    id_period_service,
    explode(assignments) as assignments
  FROM
    work_rel
),
assignments AS (
  SELECT
    id_person,
    id_period_service,
    assignments ['AssignmentId'] AS id_assignment,
    assignments ['representatives'] AS representatives
  FROM
    assignments_step1
),
representatives_step1 AS (
  SELECT
    id_person,
    id_period_service,
    id_assignment,
    explode(representatives) as representatives
  FROM
    assignments
),
representatives AS (
  SELECT
    id_person,
    id_period_service,
    id_assignment,
    representatives ['PersonId'] AS id_person_hrbp,
    representatives ['AssignmentNumber'] AS assignment_number_hrbp,
    representatives ['ResponsibilityName'] AS responsibility_name_hrbp
  FROM
    representatives_step1
  WHERE
    representatives ['ResponsibilityType'] = 'BPs' 
  QUALIFY representatives ['FromDate'] = MAX(representatives ['FromDate']) OVER (PARTITION BY id_assignment)
),
managers_direct_led AS (
  SELECT
    id_manager_assignment,
    count(*) AS qnt_directly_led
  FROM
    managers_present
  GROUP BY
    id_manager_assignment
),
salaries AS (
  SELECT
    id_assignment,
    salary_amount
  FROM
    datalake_hr_system_clean.salaries
  WHERE
    dt_from <= DATE('{load_start_date}')
    AND assignment_number NOT LIKE 'P%' 
  QUALIFY dt_from = MAX(dt_from) OVER (PARTITION BY assignment_number)
)
SELECT
  -- ids
  wr.id_period_of_service AS sk_assignment,
  -- non ids
  wr.id_person AS sk_employee,
  COALESCE(ap.id_cost_center, af.id_cost_center, '-1') AS sk_cost_center,
  COALESCE(ap.id_business_unit, af.id_business_unit, '-1') AS sk_business_unit,
  coalesce(ap.id_job, af.id_job, '-1') AS sk_job,
  CASE
    WHEN COALESCE(
      ap_manager.id_assignment,
      af_manager.id_assignment
    ) IS NULL 
      THEN '-1'
    ELSE COALESCE(ap_manager.id_person, af_manager.id_person, '-1')
  END AS sk_manager,
  CASE
    WHEN COALESCE(
      ap_manager.id_assignment,
      af_manager.id_assignment
    ) IS NULL 
      THEN '-1'
    ELSE COALESCE(
      mp.id_manager_assignment,
      mf.id_manager_assignment,
      '-1'
    )
  END AS sk_manager_assignment,
  COALESCE(rep.id_person_hrbp, '-1') AS sk_business_partner,
  COALESCE(ap_hbrp.id_assignment, '-1') AS sk_business_partner_assignment,
  CASE
    WHEN wr.worker_type = 'P' 
      THEN REPLACE(
        COALESCE(ap.dt_projected_start, af.dt_projected_start),
        '-',
        ''
      )
    ELSE REPLACE(wr.dt_start, '-', '')
  END AS sk_dt_start_work_relationship,
  CASE
    WHEN wr.worker_type = 'P' 
      THEN '-1'
    ELSE COALESCE(replace(wr.dt_termination, '-', ''), '-1')
  END AS sk_dt_termination_work_relationship,
  -- metrics
  CASE
    WHEN wr.dt_start = MAX(wr.dt_start) over (PARTITION BY wr.id_person) 
      THEN TRUE
    ELSE FALSE
  END AS is_last_work_relationship,
  CASE
    WHEN ap.assignment_status_type = 'ACTIVE' 
      THEN TRUE
    ELSE FALSE
  END AS is_active,
  CASE
    WHEN wr.worker_type = 'P' 
      THEN TRUE
    ELSE FALSE
  END AS is_pending_worker,
  CASE
    WHEN ap.career_track = 'L'
    OR mdl.qnt_directly_led > 0 
      THEN TRUE
    ELSE FALSE
  END AS is_manager,
  CASE
    WHEN wr.worker_type = 'P' 
      THEN 0
    ELSE INT(
      months_between(
        coalesce(wr.dt_termination, DATE('{load_start_date}')),
        wr.dt_start
      )
    )
  END AS assignment_age_months,
  COALESCE(mdl.qnt_directly_led, 0) AS qnt_directly_led,
  COALESCE(ap.qnt_promotions, 0) AS qnt_promotions,
  COALESCE(s.salary_amount, -1) AS salary,
  COALESCE(ap.target_plr, 0) AS target_plr,
  NOW() AS ts_load
FROM
  datalake_hr_system.work_relationships AS wr
  LEFT JOIN 
    assignments_present AS ap 
      ON wr.id_period_of_service = ap.id_period_of_service
  LEFT JOIN 
    assignments_future AS af 
      ON wr.id_period_of_service = af.id_period_of_service
  LEFT JOIN 
    managers_present AS mp 
      ON wr.id_period_of_service = mp.id_period_of_service
  LEFT JOIN 
    managers_future AS mf 
      ON wr.id_period_of_service = mf.id_period_of_service
  LEFT JOIN 
    assignments_present AS ap_manager 
      ON COALESCE(
            mp.id_manager_assignment,
            mf.id_manager_assignment
          ) = ap_manager.id_assignment
  LEFT JOIN 
    assignments_future AS af_manager 
      ON COALESCE(
            mp.id_manager_assignment,
            mf.id_manager_assignment
          ) = af_manager.id_assignment
  LEFT JOIN 
    representatives AS rep 
      ON wr.id_period_of_service = rep.id_period_service
        AND ap.id_assignment = rep.id_assignment
  LEFT JOIN 
    assignments_present AS ap_hbrp 
      ON rep.assignment_number_hrbp = ap_hbrp.assignment_number
  LEFT JOIN 
    managers_direct_led AS mdl 
      ON ap.id_assignment = mdl.id_manager_assignment
  LEFT JOIN 
    salaries AS s 
      ON COALESCE(ap.id_assignment, af.id_assignment) = s.id_assignment
WHERE
  (
    wr.dt_start <= DATE('{load_start_date}')
    AND wr.worker_type = 'E'
  )
  OR (
    COALESCE(ap.dt_projected_start, af.dt_projected_start) > DATE('{load_start_date}')
    AND wr.worker_type = 'P'
  )