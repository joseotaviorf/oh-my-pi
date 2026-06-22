SELECT
    bu.consolidated_business_unit_name AS empresa,
    es.name AS nome,
    CASE
        WHEN bu.consolidated_business_unit_name = 'QuintoAndar MG' THEN '16.788.643/0021-25'
        WHEN bu.consolidated_business_unit_name = 'QuintoAndar SC' THEN '16.788.643/0022-06'
        WHEN bu.consolidated_business_unit_name = 'QuintoAndar SP' THEN '16.788.643/0001-81'
        ELSE NULL
    END AS cnpj,
    es.gender_identity AS identidade_genero,
    es.marital_status AS estado_civil,
    es.dt_birth AS dt_nascimento,
    es.cpf,
    es.dt_hired AS dt_inicio,
    es.job_name AS cargo,
    NULLIF(LOWER(es.structure), '-1') AS departamento,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    LOWER(es.work_email) AS email,
    es.person_number AS matricula,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
WHERE
    es.dt_reference = CURRENT_DATE()
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND LOWER(es.status) = 'active'
    AND bu.consolidated_business_unit_name IN (
        'QuintoAndar SP',
        'QuintoAndar SC',
        'QuintoAndar MG'
    )
