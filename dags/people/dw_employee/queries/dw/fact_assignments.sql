WITH
  subordinates AS (
    SELECT
      id_manager_assignment AS id_assignment,
      COUNT(*) AS qnt_undirectly_led
    FROM
      datalake_hr_system.management_hierarchy
    WHERE
      not is_direct_manager
    GROUP BY
      id_manager_assignment
  )
SELECT
  am.sk_assignment,
  am.sk_employee,
  am.sk_demographic_information,
  am.sk_cost_center,
  am.sk_business_unit,
  am.sk_job,
  am.sk_manager,
  am.sk_manager_assignment,
  am.sk_business_partner,
  am.sk_business_partner_assignment,
  REPLACE(am.dt_start_work_relationship, '-', '') AS sk_start_work_relationship_date,
  REPLACE(am.dt_termination_work_relationship, '-', '') AS sk_termination_work_relationship_date,
  am.assignment_number,
  am.salary_currency,
  am.sk_last_increase_date,
  am.sk_first_promotion_date,
  am.is_last_work_relationship,
  am.is_active,
  am.is_pending_worker,
  am.is_manager,
  am.assignment_age_months,
  am.qnt_directly_led,
  COALESCE(s.qnt_undirectly_led, 0) AS qnt_undirectly_led,
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
  LEFT JOIN subordinates AS s ON s.id_assignment = am.sk_assignment
