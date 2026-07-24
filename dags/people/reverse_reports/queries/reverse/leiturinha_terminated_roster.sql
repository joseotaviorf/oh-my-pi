SELECT
    bu.consolidated_business_unit_name AS empresa,
    es.dt_terminated AS dt_desligamento,
    CASE
        WHEN LOWER(es.termination_type) = 'voluntary' THEN 'voluntario'
        WHEN LOWER(es.termination_type) = 'involuntary' THEN 'involuntario'
        ELSE LOWER(es.termination_type)
    END AS motivo_desligamento,
    es.dt_employee_hired AS dt_inicio,
    LOWER(es.job_name) AS cargo,
    es.name AS nome,
    LOWER(es.work_email) AS email,
    LOWER(es.personal_email) AS email_pessoal,
    COALESCE(es.cpf, doc.cpf) AS cpf,
    es.person_number AS matricula,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
LEFT JOIN
    dw_employee_details.dim_documentation AS doc
        ON doc.person_number = es.person_number
        AND doc.is_current = TRUE
WHERE
    es.is_current_for_employee = TRUE
    AND LOWER(es.status) = 'terminated'
    AND bu.consolidated_business_unit_name IN (
        'QuintoAndar SP',
        'QuintoAndar SC',
        'QuintoAndar MG'
    )
