SELECT
    sk_assignment,
    sk_employee,
    sk_demographic_information,
    sk_cost_center,
    sk_business_unit,
    sk_job,
    sk_manager,
    sk_manager_assignment,
    sk_disability,
    sk_work_relationship_started_date,
    sk_work_relationship_ended_date,
    sk_last_salary_increase_date,
    sk_hierarchy,
    assignment_number,
    salary_currency_code,
    is_active,
    is_pending_worker,
    is_manager,
    has_self_declared_disability,
    assignment_age_months,
    qnt_directly_led,
    qnt_undirectly_led,
    salary,
    last_salary_increase,
    pct_last_salary_increase,
    NOW() AS ts_load
FROM
    dw_employee.fact_assignments
WHERE 
    NOT is_pending_worker
    AND is_last_valid_work_relationship