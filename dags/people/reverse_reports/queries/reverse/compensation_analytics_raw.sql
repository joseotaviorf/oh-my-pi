SELECT DISTINCT
    CAST(FROM_UTC_TIMESTAMP(es.ts_load, 'America/Sao_Paulo') AS DATE) AS data_extracao,
    es.person_number AS person_number,
    es.cpf,
    es.name AS nome,
    es.job_name AS cargo,
    es.manager_name AS gestor,
    es.dt_hired AS dt_inicio,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    bu.consolidated_business_unit_name AS empresa,
    LOWER(es.work_email) AS email,
    es.band AS banda,
    REPLACE(CAST(es.amount_salary AS STRING), '.', ',') AS salario,
    de.employee_tmf_code AS registration,
    es.assignment_number AS id_colaborador,
    es.job_code AS codigo_cargo,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
LEFT JOIN
    dw_employee_details.dim_employee AS de
        ON de.sk_employee = es.sk_employee
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND LOWER(es.status) = 'active'
