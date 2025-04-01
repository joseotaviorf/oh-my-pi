WITH
promotions_step_1 AS (
  SELECT
    id_period_of_service,
    id_assignment,
    dt_effective_start,
    action_code,
    band,
    LAG(band) OVER (PARTITION BY id_assignment ORDER BY dt_effective_start) AS last_band
  FROM
    datalake_hr_system.assignments
),
promotions AS (
  SELECT
    id_period_of_service,
    COUNT(*) AS qnt_promotions
  FROM
    promotions_step_1
  WHERE
    action_code = 'PROMOTION'
    OR (band IS NOT NULL AND band <> last_band)
  GROUP BY
    id_period_of_service
),
subordinates AS (
  SELECT
    mh.id_manager_period_of_service AS id_manager_assignment,
    SUM(IF(mh.is_direct_manager AND a.assignment_status_type = 'ACTIVE', 1, 0)) AS qnt_directly_led,
    SUM(IF(NOT mh.is_direct_manager AND a.assignment_status_type = 'ACTIVE', 1, 0)) AS qnt_undirectly_led
  FROM
    datalake_hr_system.management_hierarchy AS mh
  LEFT JOIN
    datalake_hr_system.assignment_effective_status AS a
      ON a.id_assignment = mh.id_assignment
  GROUP BY
    mh.id_manager_period_of_service
),
cte_enrich_disability AS (
  SELECT DISTINCT
    sk_disability,
    id_person,
    has_self_declared_disability
  FROM datalake_hr_system.disability
  QUALIFY
    ts_last_updated = MAX(ts_last_updated) OVER (PARTITION BY id_person)
    OR ts_last_updated IS NULL
),
last_work_relationship AS (
  SELECT
    id_period_of_service
  FROM
    datalake_hr_system.work_relationships
  WHERE
    worker_type <> 'P'
    AND dt_start < DATE('{load_start_date}')
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_person ORDER BY dt_start DESC) = 1
)

SELECT
  wr.id_period_of_service AS sk_assignment,
  wr.id_person AS sk_employee,
  COALESCE(da.sk_demographic_information, '-1') AS sk_demographic_information,
  COALESCE(a.id_cost_center, '-1') AS sk_cost_center,
  COALESCE(a.id_business_unit, '-1') AS sk_business_unit,
  COALESCE(a.id_job, '-1') AS sk_job,
  COALESCE(am.id_person, '-1') AS sk_manager,
  COALESCE(am.id_period_of_service,'-1') AS sk_manager_assignment,
  COALESCE(d.sk_disability, '-1') AS sk_disability,
  sm.sk_last_increase_date,
  sm.sk_first_promotion_date,
  wr.worker_type,
  a.assignment_number AS assignment_number,
  COALESCE(sm.currency_code, -1) AS salary_currency,
  IF(lw.id_period_of_service IS NOT NULL, TRUE, FALSE) AS is_last_work_relationship,
  CASE
    WHEN a.assignment_status_type = 'ACTIVE'
    THEN TRUE
    ELSE FALSE
  END AS is_active,
  CASE
    WHEN wr.worker_type = 'P'
    THEN TRUE
    ELSE FALSE
  END AS is_pending_worker,
  CASE
    WHEN a.career_track = 'L'
      OR s.qnt_directly_led > 0
    THEN TRUE
    ELSE FALSE
  END AS is_manager,
  COALESCE(d.has_self_declared_disability, FALSE) AS has_self_declared_disability,
  IF(wr.worker_type = 'P', 0, INT(MONTHS_BETWEEN(COALESCE(wr.dt_termination, DATE('{load_start_date}')), wr.dt_start))) AS assignment_age_months,
  COALESCE(s.qnt_directly_led, 0) AS qnt_directly_led,
  COALESCE(s.qnt_undirectly_led, 0) AS qnt_undirectly_led,
  COALESCE(p.qnt_promotions, 0) AS qnt_promotions,
  COALESCE(sm.current_salary_amount, -1) AS salary,
  COALESCE(a.target_plr, 0) AS target_plr,
  COALESCE(sm.salary_reference, 0) AS salary_reference,
  COALESCE(sm.qnt_movimentations, 0) AS qnt_movimentations,
  COALESCE(sm.average_time_between_movimentations, 0) AS average_time_between_movimentations,
  COALESCE(sm.last_salary_increase, 0) AS last_increase,
  COALESCE(sm.pct_last_salary_increase, 0) AS pct_last_increase,
  COALESCE(sm.first_salary_amount, 0) AS first_salary,
  COALESCE(sm.previous_salary_amount, 0) AS last_salary,
  COALESCE(sm.range_salary_movement, 0) AS range_salary_movement,
  COALESCE(sm.first_promotion_salary, 0) AS first_promotion_salary,
  COALESCE(sm.nominal_increase_first_promotion, 0) AS nominal_increase_first_promotion,
  COALESCE(sm.pct_increase_first_promotion, 0) AS pct_increase_first_promotion,
  MONTHS_BETWEEN(IF(wr.worker_type = 'P', a.dt_projected_start, wr.dt_start), sm.dt_first_promotion) AS months_to_first_promotion,
  IF(wr.worker_type = 'P', a.dt_projected_start, wr.dt_start) AS dt_work_relationship_started,
  wr.dt_termination AS dt_work_relationship_terminated,
  NOW() AS ts_load
FROM
  datalake_hr_system.work_relationships AS wr
LEFT JOIN
  datalake_hr_system.assignment_effective_status AS a
    ON wr.id_period_of_service = a.id_period_of_service
LEFT JOIN
  datalake_hr_system.management_hierarchy AS m
    ON wr.id_period_of_service = m.id_period_of_service
      AND is_direct_manager
LEFT JOIN
  datalake_hr_system.assignment_effective_status AS am
    ON m.id_manager_assignment = am.id_assignment
LEFT JOIN
  subordinates AS s
   ON a.id_period_of_service = s.id_manager_assignment
LEFT JOIN
  promotions AS p
    ON p.id_period_of_service = wr.id_period_of_service
LEFT JOIN
  datalake_hr_system.salary_metrics AS sm
    ON a.id_assignment = sm.id_assignment
LEFT JOIN
  datalake_hr_system.demographic_attributes AS da
    ON wr.id_person = da.id_person
      AND wr.legislation_code = da.legislation_code
LEFT JOIN
  cte_enrich_disability AS d
    ON wr.id_person = d.id_person
LEFT JOIN
  last_work_relationship AS lw
    ON lw.id_period_of_service = wr.id_period_of_service
WHERE
  (wr.dt_start <= DATE('{load_start_date}')
    AND wr.worker_type IN ('E', 'C'))
  OR (a.dt_projected_start > DATE('{load_start_date}')
    AND wr.worker_type = 'P')
