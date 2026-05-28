WITH
terminated_for_transfer AS (
    SELECT
        id_period_of_service_next,
        previous_dt_started,
        is_transfered
    FROM (
        SELECT
            aa_next.id_period_of_service AS id_period_of_service_next,
            ps_prev.dt_started AS previous_dt_started,
            (aa.action_code = 'GLB_TRANSFER') AS is_transfered,
            ROW_NUMBER() OVER (PARTITION BY aa.id_period_of_service ORDER BY aa.dt_effective_started ASC) AS _rn
        FROM
            datalake_pin_core_clean.all_assignments AS aa
        INNER JOIN
            datalake_pin_core_clean.all_assignments AS aa_next
                ON aa_next.id_person = aa.id_person
                AND aa_next.assignment_sequence = aa.assignment_sequence + 1
        LEFT JOIN
            datalake_pin_core_clean.periods_of_service AS ps_prev
                ON ps_prev.id_period_of_service = aa.id_period_of_service
        WHERE
            aa.assignment_status_type = 'INACTIVE'
            AND aa.action_code = 'GLB_TRANSFER'
    )
    WHERE _rn = 1
)

SELECT
    fa.sk_assignment,
    fa.sk_employee,
    fa.sk_demographic_information,
    fa.sk_cost_center,
    fa.sk_business_unit,
    fa.sk_job,
    fa.sk_manager,
    fa.sk_manager_assignment,
    fa.sk_disability,
    COALESCE(
        DATE_FORMAT(tfac.previous_dt_started, 'yyyyMMdd'),
        fa.sk_work_relationship_started_date
    ) AS sk_work_relationship_started_date,
    fa.sk_work_relationship_ended_date,
    fa.sk_last_salary_increase_date,
    fa.sk_hierarchy,
    fa.assignment_number,
    fa.salary_currency_code,
    fa.is_active,
    fa.is_pending_worker,
    fa.is_manager,
    CASE 
      WHEN fa.is_pending_worker THEN 0
      ELSE FLOOR(MONTHS_BETWEEN(
        COALESCE(
          TO_DATE(CAST(fa.sk_work_relationship_ended_date AS STRING), 'yyyyMMdd'),
          DATE('{load_start_date}')
        ),
        COALESCE(
          tfac.previous_dt_started,
          TO_DATE(CAST(fa.sk_work_relationship_started_date AS STRING), 'yyyyMMdd')
        )
      ))
    END AS assignment_age_months,
    fa.qnt_directly_led,
    fa.qnt_undirectly_led,
    fa.salary,
    fa.last_salary_increase,
    fa.pct_last_salary_increase,
    COALESCE(tfac.is_transfered, FALSE) AS is_transfered,
    fa.has_active_manager,
    COALESCE(tfac.previous_dt_started, fa.dt_work_relationship_started) AS dt_work_relationship_started,
    fa.dt_work_relationship_ended AS dt_work_relationship_ended,
    fa.dt_last_salary_increase AS dt_last_salary_increase,
    NOW() AS ts_load
FROM
    dw_employee.fact_assignments AS fa
LEFT JOIN
    terminated_for_transfer AS tfac
        ON tfac.id_period_of_service_next = fa.sk_assignment
WHERE 
    NOT fa.is_pending_worker
    AND fa.is_last_valid_work_relationship