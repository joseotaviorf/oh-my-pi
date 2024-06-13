WITH salaries AS (
  SELECT
    id_assignment,
    currency_code
  FROM
    datalake_hr_system_clean.salaries
  WHERE
    dt_from <= DATE('{load_start_date}')
    AND assignment_number NOT LIKE 'P%' 
  QUALIFY dt_from = MAX(dt_from) OVER (PARTITION BY assignment_number)
),
assignments AS (
  SELECT
    a.id_assignment,
    a.id_period_of_service,
    a.assignment_number,
    a.assignment_type,
    a.assignment_status_type_code,
    a.assignment_status_type,
    a.union_name,
    a.brand,
    a.band,
    a.is_primary_assignment,
    a.dt_effective_start,
    a.dt_effective_end,
    a.dt_projected_start,
    a.action_code,
    a.year,
    a.month
  FROM
    datalake_hr_system.assignments a
),
assignments_present AS (
  SELECT
    DISTINCT a.id_assignment,
    a.id_period_of_service,
    a.assignment_number,
    a.assignment_type,
    a.assignment_status_type_code,
    a.assignment_status_type,
    a.band,
    a.union_name,
    a.is_primary_assignment,
    a.dt_effective_start,
    a.dt_projected_start,
    a.action_code,
    al.description AS action_description
  FROM
    assignments AS a
    LEFT JOIN 
      datalake_hr_system_clean.actions_lov al 
        ON a.action_code = al.action_code
  WHERE
    dt_effective_start < DATE('{load_start_date}') 
  QUALIFY dt_effective_start = MAX(dt_effective_start) over (PARTITION BY id_assignment)
),
assignment_future AS (
  SELECT
    DISTINCT a.id_assignment,
    a.id_period_of_service,
    a.assignment_number,
    a.assignment_type,
    a.assignment_status_type_code,
    a.assignment_status_type,
    a.union_name,
    a.band,
    a.is_primary_assignment,
    a.dt_effective_start,
    a.dt_projected_start,
    a.action_code,
    al.description AS action_description
  FROM
    assignments AS a
    LEFT JOIN 
      datalake_hr_system_clean.actions_lov al 
        ON a.action_code = al.action_code
  WHERE
    dt_effective_start >= DATE('{load_start_date}') 
  QUALIFY dt_effective_start = MAX(dt_effective_start) over (PARTITION BY a.id_assignment)
)
SELECT
  wr.id_period_of_service AS sk_assignment,
  wr.legislation_code,
  wr.worker_type,
  COALESCE(ap.assignment_number, af.assignment_number) AS assignment_number,
  COALESCE(ap.band, af.band) AS band,
  COALESCE(
    ap.assignment_status_type_code,
    af.assignment_status_type_code
  ) AS assignment_status_type_code,
  COALESCE(
    ap.assignment_status_type,
    af.assignment_status_type
  ) AS assignment_status_type,
  COALESCE(ap.union_name, af.union_name, '-1') AS union_name,
  COALESCE(
    CASE
      WHEN wr.dt_termination < DATE('{load_start_date}')
        AND wr.worker_type = 'E' 
          THEN ap.action_description
      WHEN wr.dt_termination >= DATE('{load_start_date}')
        AND wr.worker_type = 'E' 
          THEN af.action_description
    END,
    '-1'
  ) AS dismissal_type,
  COALESCE(s.currency_code, '-1') AS salary_currency
FROM
  datalake_hr_system.work_relationships wr
  LEFT JOIN 
    assignments_present AS ap 
      ON wr.id_period_of_service = ap.id_period_of_service
  LEFT JOIN 
    assignment_future AS af 
      ON wr.id_period_of_service = af.id_period_of_service
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
