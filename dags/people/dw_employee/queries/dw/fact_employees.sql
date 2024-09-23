WITH
    cte_days_between_assignments AS (
        SELECT
            sk_employee,
            sk_assignment,
            dt_start_work_relationship,
            dt_termination_work_relationship,
            LEAD (dt_start_work_relationship, 1) OVER (
                PARTITION BY
                    sk_employee
                ORDER BY
                    dt_start_work_relationship
            ) AS next_dt_start_work_relationship,
            COALESCE(
                DATEDIFF (
                    DAY,
                    dt_termination_work_relationship,
                    next_dt_start_work_relationship
                ),
                -1
            ) AS days_untill_next_work_relationship
        FROM
            datalake_hr_system.assignment_metrics
    ),
    cte_invalid_relationships AS (
        SELECT
            sk_employee,
            sk_assignment,
            dt_start_work_relationship AS max_invalid_dt_start_work_relationship
        FROM
            cte_days_between_assignments
        WHERE
            days_untill_next_work_relationship > 7
        QUALIFY
            ROW_NUMBER() OVER ( PARTITION BY sk_employee ORDER BY dt_start_work_relationship DESC ) = 1
    ),
    cte_dt_hiring AS (
        SELECT
            ba.sk_employee,
            MIN(ba.dt_start_work_relationship) AS dt_hiring
        FROM
            cte_days_between_assignments AS ba
            LEFT JOIN
                cte_invalid_relationships AS ur
                    ON ba.sk_employee = ur.sk_employee
        WHERE
            ur.max_invalid_dt_start_work_relationship IS NULL
            OR ba.dt_start_work_relationship > ur.max_invalid_dt_start_work_relationship
        GROUP BY
            ba.sk_employee
    ),
    salary_raw_for_employee AS (
        SELECT
            s.id_assignment,
            a.id_person,
            a.dt_effective_start AS start_date,
            s.grade_name AS grade,
            s.salary_amount AS salary,
            s.adjustment_amount AS nominal_increase,
            s.adjustment_percentage AS percentage_increase,
            s.compa_ratio AS position_in_band,
            s.salary_range_mid_point AS salary_reference,
            s.dt_from AS change_date
        FROM
            datalake_hr_system_clean.salaries AS s
        INNER JOIN
            datalake_hr_system.assignments AS a
                ON s.id_assignment = a.id_assignment
        LEFT JOIN
            cte_dt_hiring AS h
                ON h.dt_hiring <= a.dt_effective_start
                    AND h.sk_employee = a.id_person
        WHERE
            dt_from <= DATE ('{load_start_date}')
            AND s.assignment_number NOT LIKE 'P%'
        QUALIFY
            a.dt_effective_start = MAX(a.dt_effective_start) OVER (PARTITION BY a.id_person)
            AND s.dt_from = MAX(s.dt_from) OVER (PARTITION BY a.id_person)
    ),
    cte_movements_step_0_for_employee AS (
        SELECT
            *,
            COUNT(*) OVER (
                PARTITION BY
                    id_person
            ) AS qnt_movimentations,
            ROW_NUMBER() OVER (
                PARTITION BY
                    id_person
                ORDER BY
                    change_date
            ) AS order,
            LAG (change_date) OVER (
                PARTITION BY
                    id_person
                ORDER BY
                    change_date
            ) AS previous_change_date,
            FIRST_VALUE (change_date) OVER (
                PARTITION BY
                    id_person
                ORDER BY
                    change_date
            ) AS first_change_date,
            LAST_VALUE (change_date) OVER (
                PARTITION BY
                    id_person
                ORDER BY
                    change_date
            ) AS last_change_date
        FROM
            salary_raw_for_employee
    ),
    cte_movements_step_1_for_employee AS (
        SELECT
            *,
            CASE
                WHEN percentage_increase < 5 THEN NULL
                ELSE order
            END AS adjusted_order,
            CASE
                WHEN qnt_movimentations > 1 THEN FLOOR(
                    DATEDIFF (month, previous_change_date, change_date)
                ) + 1
                ELSE NULL
            END AS period,
            CASE
                WHEN qnt_movimentations > 1 THEN ROUND(
                    AVG(
                        FLOOR(
                            DATEDIFF (month, previous_change_date, change_date)
                        ) + 1
                    ) OVER (
                        PARTITION BY
                            id_person
                    ),
                    1
                )
                ELSE 0
            END AS average_time_between_movimentations,
            MAX(
                CASE
                    WHEN change_date = last_change_date THEN change_date
                    ELSE NULL
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) AS dt_last_increase,
            MAX(
                CASE
                    WHEN change_date = last_change_date THEN nominal_increase
                    ELSE 0
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) AS last_increase,
            MAX(
                CASE
                    WHEN change_date = last_change_date THEN percentage_increase
                    ELSE 0
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) AS pct_last_increase,
            MAX(
                CASE
                    WHEN change_date = last_change_date THEN salary
                    ELSE 0
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) AS last_salary,
            MAX(
                CASE
                    WHEN change_date = first_change_date THEN salary
                    ELSE 0
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) AS first_salary,
            MAX(
                CASE
                    WHEN change_date = last_change_date THEN salary
                    ELSE 0
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) - MAX(
                CASE
                    WHEN change_date = first_change_date THEN salary
                    ELSE 0
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) AS range_salary_movement,
            MAX(
                CASE
                    WHEN order = 1 THEN change_date
                    ELSE NULL
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) AS dt_first_promotion
        FROM
            cte_movements_step_0_for_employee
    ),
    cte_movements_for_employee AS (
        SELECT
            *,
            CASE
                WHEN qnt_movimentations > 1 THEN FLOOR(DATEDIFF (month, start_date, dt_first_promotion)) + 1
                ELSE NULL
            END AS months_to_first_promotion,
            MAX(
                CASE
                    WHEN change_date = dt_first_promotion THEN nominal_increase
                    ELSE 0
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) AS nominal_increase_first_promotion,
            MAX(
                CASE
                    WHEN change_date = dt_first_promotion THEN salary
                    ELSE 0
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) AS first_promotion_salary,
            MAX(
                CASE
                    WHEN change_date = dt_first_promotion THEN percentage_increase
                    ELSE 0
                END
            ) OVER (
                PARTITION BY
                    id_person
            ) AS pct_increase_first_promotion
        FROM
            cte_movements_step_1_for_employee
    ),
    salaries_for_employee AS (
        SELECT DISTINCT
            id_person,
            qnt_movimentations,
            average_time_between_movimentations,
            first_salary,
            range_salary_movement,
            first_promotion_salary,
            nominal_increase_first_promotion,
            pct_increase_first_promotion,
            months_to_first_promotion,
            dt_first_promotion
        FROM
            cte_movements_for_employee
        WHERE
            qnt_movimentations = 1
            OR change_date = dt_last_increase
    ),
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
    am.sk_disability,
    REPLACE (am.dt_start_work_relationship, '-', '') AS sk_work_relationship_started_date,
    REPLACE (am.dt_termination_work_relationship, '-', '') AS sk_dt_termination_work_relationship,
    am.sk_last_increase_date,
    REPLACE (se.dt_first_promotion, '-', '') AS sk_dt_first_promotion,
    h.sk_hierarchy,
    am.assignment_number,
    am.salary_currency,
    am.is_last_work_relationship,
    am.is_active,
    am.is_pending_worker,
    am.is_manager,
    am.has_self_declared_disability,
    am.assignment_age_months,
    am.qnt_directly_led,
    COALESCE(s.qnt_undirectly_led, 0) AS qnt_undirectly_led,
    am.qnt_promotions,
    am.salary,
    am.target_plr,
    am.salary_reference AS salary_range_midpoint,
    se.qnt_movimentations,
    se.average_time_between_movimentations,
    am.last_increase,
    am.pct_last_increase,
    se.first_salary,
    am.last_salary,
    se.range_salary_movement,
    se.first_promotion_salary,
    se.nominal_increase_first_promotion,
    se.pct_increase_first_promotion,
    se.months_to_first_promotion,
    NOW () AS ts_load
FROM
    datalake_hr_system.assignment_metrics AS am
LEFT JOIN
    salaries_for_employee AS se
        ON am.sk_employee = se.id_person
LEFT JOIN
    subordinates AS s
        ON s.id_assignment = am.sk_assignment
LEFT JOIN
    datalake_hr_system.hierarchy_ids AS h
        ON h.sk_assignment = am.sk_assignment
WHERE
    am.is_last_work_relationship
