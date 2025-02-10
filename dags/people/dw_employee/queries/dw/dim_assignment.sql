WITH
  salaries AS (
    SELECT
      id_assignment,
      currency_code,
      action_reason
    FROM
      datalake_hr_system_clean.salaries
    WHERE
      dt_from <= DATE ('{load_start_date}')
      AND assignment_number NOT LIKE 'P%'
    QUALIFY
      MAX(dt_from) OVER (PARTITION BY assignment_number) = dt_from
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
      IF (
        business_unit_name IN ('Classifieds Latam', 'Benvi MX'),
        ts_last_update,
        TIMESTAMP(dt_effective_start)
      ) AS ts_valid_from
    FROM
      datalake_hr_system.assignments a
  ),
  assignments_present AS (
    SELECT DISTINCT
      a.id_assignment,
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
      al.description AS action_description,
      a.ts_valid_from
    FROM
      assignments AS a
    LEFT JOIN
      datalake_hr_system_clean.actions_lov AS al
        ON a.action_code = al.action_code
    WHERE
      DATE(a.ts_valid_from) < DATE('{load_start_date}')
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY
          id_assignment
        ORDER BY
          ts_valid_from DESC,
          dt_effective_start DESC
      ) = 1
  ),
  assignment_future AS (
    SELECT DISTINCT
      a.id_assignment,
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
      al.description AS action_description,
      a.ts_valid_from
    FROM
      assignments AS a
    LEFT JOIN
      datalake_hr_system_clean.actions_lov AS al
        ON a.action_code = al.action_code
    WHERE
      DATE(a.ts_valid_from) >= DATE('{load_start_date}')
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY
        id_assignment
      ORDER BY
        ts_valid_from DESC,
        dt_effective_start DESC
    ) = 1
  )
SELECT
  wr.id_period_of_service AS sk_assignment,
  ei.legacy_registration,
  wr.legislation_code,
  wr.worker_type,
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
      WHEN wr.dt_termination < DATE ('{load_start_date}')
      AND wr.worker_type IN ('E', 'C')
      THEN ap.action_description
      WHEN wr.dt_termination >= DATE ('{load_start_date}')
      AND wr.worker_type IN ('E', 'C')
      THEN af.action_description
    END,
    '-1'
  ) AS dismissal_type,
  s.action_reason AS reason_last_increase
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
LEFT JOIN
  datalake_hr_system.employee_ids AS ei
    ON ei.id_period_of_service = wr.id_period_of_service
WHERE
  (
    wr.dt_start <= DATE ('{load_start_date}')
    AND wr.worker_type IN ('E', 'C')
  )
  OR (
    COALESCE(ap.dt_projected_start, af.dt_projected_start) > DATE ('{load_start_date}')
    AND wr.worker_type = 'P'
  )
