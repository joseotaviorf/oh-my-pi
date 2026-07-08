-- Aba 2 "Agendamentos": approved vacation (and intern recess) schedules, past and future.
-- Companies in scope: MLSP business unit and the Brazilian QuintoAndar business units (GRPQA).
WITH active_assignment AS (
    SELECT
        snap.assignment_number,
        snap.sk_employee,
        snap.sk_job_version,
        snap.sk_business_unit,
        snap.sk_hierarchy_version
    FROM
        dw_employee_details.fact_assignment_snapshots AS snap
    WHERE
        snap.is_current_for_employee = TRUE
        AND snap.is_active = TRUE
),
in_scope_assignment AS (
    SELECT
        aa.assignment_number,
        aa.sk_employee,
        aa.sk_job_version,
        aa.sk_hierarchy_version,
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
),
approved_vacation AS (
    SELECT
        far.sk_absence_type,
        far.person_number,
        far.assignment_number,
        far.days_requested,
        far.days_cash_out_requested,
        far.is_13th_salary_advance,
        far.dt_absence_started,
        far.dt_absence_ended,
        far.dt_acquisitive_period_started,
        far.dt_acquisitive_period_ended
    FROM
        dw_time.fact_absence_requests AS far
    WHERE
        far.is_approved = TRUE
        AND far.is_withdrawn = FALSE
)
SELECT
    isa.business_unit_name AS business_unit,
    av.person_number,
    av.assignment_number,
    emp.name AS employee_name,
    emp.work_email,
    job.job_name,
    dat.absence_type,
    av.dt_absence_started,
    av.dt_absence_ended,
    av.days_requested,
    av.days_cash_out_requested,
    av.is_13th_salary_advance,
    av.dt_acquisitive_period_started AS acquisitive_period_start,
    av.dt_acquisitive_period_ended AS acquisitive_period_end,
    CASE
        WHEN av.dt_absence_ended < CURRENT_DATE() THEN 'Concluída'
        WHEN av.dt_absence_started > CURRENT_DATE() THEN 'Agendada'
        ELSE 'Em andamento'
    END AS schedule_status,
    mgr_emp.name AS manager_name,
    mgr_emp.work_email AS manager_email,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    approved_vacation AS av
INNER JOIN
    dw_time.dim_absence_type AS dat
        ON av.sk_absence_type = dat.sk_absence_type
        AND dat.absence_type IN ('Férias', 'Recesso de Estagiário')
INNER JOIN
    in_scope_assignment AS isa
        ON av.assignment_number = isa.assignment_number
LEFT JOIN
    dw_employee_details.dim_employee AS emp
        ON isa.sk_employee = emp.sk_employee
LEFT JOIN
    dw_compensation.dim_job AS job
        ON isa.sk_job_version = job.sk_job_version
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS mh
        ON mh.assignment_number = isa.assignment_number
        AND mh.is_current = TRUE
LEFT JOIN
    dw_employee_details.fact_assignment_snapshots AS mgr_snap
        ON mgr_snap.assignment_number = mh.manager_assignment_number
        AND mgr_snap.is_current_for_assignment = TRUE
LEFT JOIN
    dw_employee_details.dim_employee AS mgr_emp
        ON mgr_snap.sk_employee = mgr_emp.sk_employee
ORDER BY
    isa.business_unit_name,
    emp.name,
    av.dt_absence_started
