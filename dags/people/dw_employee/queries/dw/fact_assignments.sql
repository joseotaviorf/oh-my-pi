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
),
assignments AS (
  SELECT DISTINCT
      id_assignment,
      id_period_of_service
  FROM
      datalake_hr_system.assignments
),
ranked_managers AS (
    SELECT
        mh.id_assignment,
        mh.id_period_of_service,
        mh.id_manager_assignment,
        a.id_period_of_service AS id_period_of_service_manager,
        mh.separation_degree,
        ROW_NUMBER() OVER (
            PARTITION BY
                mh.id_assignment
            ORDER BY
                mh.separation_degree DESC
        ) as rn
    FROM
        datalake_hr_system.management_hierarchy AS mh
    LEFT JOIN
        assignments AS a
            ON a.id_assignment = mh.id_manager_assignment
),
managers_long AS (
    SELECT
        id_period_of_service,
        MAX(
            CASE
                WHEN rn = 1 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_0,
        MAX(
            CASE
                WHEN rn = 2 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_1,
        MAX(
            CASE
                WHEN rn = 3 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_2,
        MAX(
            CASE
                WHEN rn = 4 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_3,
        MAX(
            CASE
                WHEN rn = 5 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_4,
        MAX(
            CASE
                WHEN rn = 6 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_5,
        MAX(
            CASE
                WHEN rn = 7 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_6,
        MAX(
            CASE
                WHEN rn = 8 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_7,
        MAX(
            CASE
                WHEN rn = 9 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_8,
        MAX(
            CASE
                WHEN rn = 10 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_9
    FROM
        ranked_managers
    GROUP BY
        id_period_of_service
)

SELECT
  am.sk_assignment,
  am.sk_employee,
  am.sk_demographic_information,
  COALESCE(d.sk_disability, -1) AS sk_disability,
  am.sk_cost_center,
  am.sk_business_unit,
  am.sk_job,
  am.sk_manager,
  am.sk_manager_assignment,
  am.sk_business_partner,
  am.sk_business_partner_assignment,
  REPLACE(am.dt_start_work_relationship, '-', '') AS sk_start_work_relationship_date,
  REPLACE(am.dt_termination_work_relationship, '-', '') AS sk_termination_work_relationship_date,
  MD5(
    CONCAT(
      COALESCE(sk_assignment_leadership_order_0, -1),
      COALESCE(sk_assignment_leadership_order_1, -1),
      COALESCE(sk_assignment_leadership_order_2, -1),
      COALESCE(sk_assignment_leadership_order_3, -1),
      COALESCE(sk_assignment_leadership_order_4, -1),
      COALESCE(sk_assignment_leadership_order_5, -1),
      COALESCE(sk_assignment_leadership_order_6, -1),
      COALESCE(sk_assignment_leadership_order_7, -1),
      COALESCE(sk_assignment_leadership_order_8, -1),
      COALESCE(sk_assignment_leadership_order_9, -1)
    )
  ) AS sk_hierarchy,
  am.assignment_number,
  am.salary_currency,
  am.sk_last_increase_date,
  am.sk_first_promotion_date,
  am.is_last_work_relationship,
  am.is_active,
  am.is_pending_worker,
  am.is_manager,
  COALESCE(d.has_self_declared_disability, FALSE) AS has_self_declared_disability,
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
  LEFT JOIN
    subordinates AS s
      ON s.id_assignment = am.sk_assignment
  LEFT JOIN
    managers_long AS ml
      ON ml.id_period_of_service = am.sk_assignment
  LEFT JOIN
    datalake_hr_system.disability AS d
      ON d.id_person = am.sk_employee
