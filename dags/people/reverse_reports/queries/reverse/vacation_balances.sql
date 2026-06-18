-- Aba 1 "Painel Geral": vacation balances per active employee and acquisitive period.
-- Companies in scope: MLSP business unit and the Brazilian QuintoAndar business units (GRPQA).
WITH active_assignment AS (
    SELECT
        snap.assignment_number,
        snap.sk_employee,
        snap.sk_job_version,
        snap.sk_cost_center_version,
        snap.sk_business_unit,
        snap.sk_hierarchy_version,
        snap.dt_hired
    FROM
        dw_employee_details.fact_assignment_snapshots AS snap
    WHERE
        snap.is_current = TRUE
        AND snap.is_primary_assignment_for_snapshot = TRUE
        AND (snap.dt_terminated IS NULL OR snap.dt_terminated >= CURRENT_DATE())
),
in_scope_assignment AS (
    SELECT
        aa.assignment_number,
        aa.sk_employee,
        aa.sk_job_version,
        aa.sk_cost_center_version,
        aa.sk_hierarchy_version,
        aa.dt_hired,
        bu.business_unit_name
    FROM
        active_assignment AS aa
    INNER JOIN
        dw_organization.dim_business_unit AS bu
            ON aa.sk_business_unit = bu.sk_business_unit
    WHERE
        bu.business_unit_name IN (
            'MLSP',
            'QuintoAndar SP',
            'QuintoAndar MG',
            'QuintoAndar SC'
        )
)
SELECT
    isa.business_unit_name AS business_unit,
    fvb.person_number,
    fvb.assignment_number,
    emp.name AS employee_name,
    emp.work_email,
    job.job_name,
    cc.cost_center_code,
    cc.cost_center_name,
    isa.dt_hired,
    mgr_emp.name AS manager_name,
    mgr_emp.work_email AS manager_email,
    fvb.dt_vacation_period_started AS acquisitive_period_start,
    fvb.dt_vacation_period_ended AS acquisitive_period_end,
    fvb.dt_vacation_period_expiration AS concessive_period_deadline,
    fvb.days_balance,
    fvb.vacation_status,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    dw_time.fact_vacation_balances AS fvb
INNER JOIN
    in_scope_assignment AS isa
        ON fvb.assignment_number = isa.assignment_number
LEFT JOIN
    dw_employee_details.dim_employee AS emp
        ON isa.sk_employee = emp.sk_employee
LEFT JOIN
    dw_compensation.dim_job AS job
        ON isa.sk_job_version = job.sk_job_version
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON isa.sk_cost_center_version = cc.sk_cost_center_version
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS mh
        ON mh.assignment_number = isa.assignment_number
        AND mh.is_current = TRUE
LEFT JOIN
    dw_employee_details.fact_assignment_snapshots AS mgr_snap
        ON mgr_snap.assignment_number = mh.manager_assignment_number
        AND mgr_snap.is_current = TRUE
LEFT JOIN
    dw_employee_details.dim_employee AS mgr_emp
        ON mgr_snap.sk_employee = mgr_emp.sk_employee
ORDER BY
    isa.business_unit_name,
    emp.name,
    fvb.dt_vacation_period_started
