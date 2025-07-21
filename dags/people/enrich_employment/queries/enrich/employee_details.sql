WITH 
terminations AS (
  SELECT
    aa.id_period_of_service,
    aa.action_code,
    al.description
  FROM
    datalake_pin_core_clean.all_assignments AS aa
  LEFT JOIN
    datalake_hr_system_clean.actions_lov AS al
      ON al.action_code = aa.action_code
  WHERE
    aa.is_primary
    AND aa.assignment_type = 'E'
    AND aa.dt_effective_ended >= DATE('{load_end_date}')
    AND aa.updated_by <> 'FUSION_APPS_HCM_ESS_LOADER_APPID'
    AND (
      (
        aa.action_code IN ('TERMINATION', 'RESIGNATION', 'DEATH')
        AND aa.assignment_status_type = 'INACTIVE'
      )
      OR (
        aa.action_code = 'GLB_TRANSFER'
        AND aa.reason_code = 'EXPATRIADO'
        AND aa.assignment_status_type = 'ACTIVE'
      )
    ) 
    QUALIFY 
      ROW_NUMBER() OVER(
        PARTITION BY id_period_of_service, assignment_status_type 
        ORDER BY dt_effective_ended ASC
      ) = 1
),
current_assignments AS (
  SELECT 
    id_period_of_service, 
    legislation_code, 
    assignment_status_type,
    dt_projected_started
  FROM 
    datalake_pin_core_clean.all_assignments
  WHERE
    (
      (
        dt_effective_started <= DATE('{load_start_date}')
        AND assignment_type IN ('E', 'C')
      )
      OR (
        dt_projected_started > DATE('{load_start_date}')
        AND assignment_type = 'P'
      )
    )
    AND dt_effective_ended >= DATE('{load_end_date}')
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY id_period_of_service 
      ORDER BY dt_effective_ended ASC
    ) = 1
)

SELECT
  ids.id_period_of_service,
  ids.id_assignment,
  ids.assignment_number,
  ids.legacy_registration,
  ca.legislation_code,
  ids.assignment_type,
  ca.assignment_status_type,
  t.description AS dismissal_type,
  IF(ca.assignment_status_type = 'ACTIVE', TRUE, FALSE) AS is_active,
  ca.dt_projected_started,
  pp.dt_started,
  pp.dt_actual_termination,
  pp.dt_notified_termination,
  NOW() AS ts_load
FROM 
  datalake_employee_registration.identifier_mapping AS ids
INNER JOIN
  current_assignments AS ca 
    ON ca.id_period_of_service = ids.id_period_of_service
LEFT JOIN 
  terminations AS t 
    ON t.id_period_of_service = ids.id_period_of_service
LEFT JOIN 
  datalake_pin_core_clean.periods_of_service AS pp 
    ON pp.id_period_of_service = ids.id_period_of_service
WHERE 
  NOT ids.is_user_test