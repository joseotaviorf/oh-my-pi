-- Full employee roster for the AppSheet Portugal vacation management app (VacationManagement-PT).
SELECT
    bu.consolidated_business_unit_name AS empresa,
    LOWER(snap.assignment_number) AS id_colaborador,
    emp.name AS nome,
    snap.person_number AS matricula,
    emp.work_email AS email,
    CASE
        WHEN snap.is_active = TRUE THEN 'ativo'
        ELSE 'desligado'
    END AS status,
    LOWER(mh.manager_assignment_number) AS id_gestor,
    mgr_emp.name AS gestor,
    snap.dt_original_hire AS dt_inicio,
    snap.dt_terminated AS dt_desligamento,
    '' AS salario,
    mgr_emp.work_email AS email_gestor,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    dw_employee_details.fact_assignment_snapshots AS snap
LEFT JOIN
    dw_employee_details.dim_employee AS emp
        ON snap.sk_employee = emp.sk_employee
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON snap.sk_business_unit = bu.sk_business_unit
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS mh
        ON mh.assignment_number = snap.assignment_number
        AND mh.is_current = TRUE
LEFT JOIN
    dw_employee_details.fact_assignment_snapshots AS mgr_snap
        ON mgr_snap.assignment_number = mh.manager_assignment_number
        AND mgr_snap.is_current = TRUE
LEFT JOIN
    dw_employee_details.dim_employee AS mgr_emp
        ON mgr_snap.sk_employee = mgr_emp.sk_employee
WHERE
    snap.is_current = TRUE
    AND snap.is_primary_assignment_for_snapshot = TRUE
ORDER BY
    bu.consolidated_business_unit_name,
    emp.name
