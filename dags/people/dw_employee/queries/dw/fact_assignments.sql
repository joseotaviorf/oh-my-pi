WITH
latest_assignments AS (
    SELECT
        id_assignment, assignment_status_type
    FROM
        datalake_hr_system.assignments
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY id_assignment
            ORDER BY dt_effective_start DESC, ts_last_update DESC) = 1
)

SELECT
  am.sk_assignment,
  am.sk_employee,
  am.sk_demographic_information,
  am.sk_disability,
  am.sk_cost_center,
  am.sk_business_unit,
  am.sk_job,
  am.sk_manager,
  am.sk_manager_assignment,
  REPLACE(am.dt_work_relationship_started, '-', '') AS sk_start_work_relationship_date,
  REPLACE(am.dt_work_relationship_ended, '-', '') AS sk_termination_work_relationship_date,
  h.sk_hierarchy,
  am.assignment_number,
  am.salary_currency,
  am.sk_last_increase_date,
  am.sk_first_promotion_date,
  am.is_last_work_relationship,
  am.is_active,
  am.is_pending_worker,
  am.is_manager,
  am.has_self_declared_disability,
  am.assignment_age_months,
  am.qnt_directly_led,
  am.qnt_undirectly_led,
  am.salary,
  am.target_plr,
  am.salary_reference,
  am.qnt_movimentations,
  am.average_time_between_movimentations,
  am.last_increase,
  am.pct_last_increase,
  am.first_salary,
  am.last_salary,
  am.range_salary_movement,
  am.first_promotion_salary,
  am.nominal_increase_first_promotion,
  am.pct_increase_first_promotion,
  am.months_to_first_promotion,
  NOW () AS ts_load
FROM
  datalake_hr_system.assignment_metrics AS am
LEFT JOIN
  datalake_hr_system.hierarchy_ids AS h
    ON h.sk_assignment = am.sk_assignment
