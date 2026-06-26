SELECT
    es.person_number,
    es.assignment_number,
    LOWER(es.work_email) AS email,
    es.name AS nome,
    es.job_name AS cargo,
    es.job_code,
    es.band AS banda,
    es.business_unit_name AS empresa,
    CASE
        WHEN es.is_active = TRUE THEN 'ativo'
        ELSE 'desligado'
    END AS status,
    es.sk_hired_date AS sk_work_relationship_started_date,
    es.sk_terminated_date AS sk_work_relationship_ended_date,
    es.termination_reason_name AS motivo_desligamento,
    es.cost_center_name AS centro_de_custo,
    es.manager_assignment_number AS gestor_assignment_number,
    mgr_emp.person_number AS gestor_person_number,
    es.manager_name AS gestor,
    LOWER(es.manager_work_email) AS email_gestor,
    LOWER(es.personal_email) AS email_pessoal,
    es.dt_birth AS dt_nascimento,
    es.amount_salary AS salario,
    fc.currency_code AS moeda,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_employee_details.fact_assignment_snapshots AS mgr_fas
        ON mgr_fas.assignment_number = es.manager_assignment_number
        AND mgr_fas.is_current = TRUE
LEFT JOIN
    dw_employee_details.dim_employee AS mgr_emp
        ON mgr_emp.sk_employee = mgr_fas.sk_employee
LEFT JOIN
    dw_employee_details.fact_assignment_snapshots AS fas
        ON fas.assignment_number = es.assignment_number
        AND fas.is_current = TRUE
LEFT JOIN
    dw_compensation.fact_compensations AS fc
        ON fc.sk_compensation = fas.sk_compensation_version
        AND fas.sk_compensation_version <> '-1'
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
