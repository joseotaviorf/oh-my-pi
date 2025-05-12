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
  REPLACE(am.dt_work_relationship_started, '-', '') AS sk_work_relationship_started_date,
  REPLACE(am.dt_work_relationship_terminated, '-', '') AS sk_work_relationship_ended_date,
  h.sk_hierarchy,
  am.assignment_number,
  am.salary_currency AS salary_currency_code,
  am.sk_last_increase_date AS sk_last_salary_increase_date,
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
  am.last_increase AS last_salary_increase,
  am.pct_last_increase AS pct_last_salary_increase,
  NOW() AS ts_load
FROM
  datalake_hr_system.assignment_metrics AS am
LEFT JOIN
  datalake_hr_system.hierarchy_ids AS h
    ON h.sk_assignment = am.sk_assignment
