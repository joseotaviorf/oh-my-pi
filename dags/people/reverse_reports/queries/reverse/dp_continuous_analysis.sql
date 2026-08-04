-- Full employee roster for DP continuous analysis (tab data).
SELECT
    UPPER(es.assignment_number) AS assignment_number,
    es.person_number AS person_number,
    LOWER(es.name) AS nome,
    LOWER(es.work_email) AS email,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    es.dt_employee_hired AS dt_inicio,
    es.dt_terminated AS dt_desligamento,
    CASE
        WHEN LOWER(es.termination_type) = 'voluntary' THEN 'voluntario'
        WHEN LOWER(es.termination_type) = 'involuntary' THEN 'involuntario'
        ELSE LOWER(es.termination_type)
    END AS motivo_desligamento,
    CASE es.country
        WHEN 'Brazil'        THEN 'brasil'
        WHEN 'Argentina'     THEN 'argentina'
        WHEN 'Mexico'        THEN 'mexico'
        WHEN 'Portugal'      THEN 'portugal'
        WHEN 'Peru'          THEN 'peru'
        WHEN 'Uruguay'       THEN 'uruguai'
        WHEN 'Ecuador'       THEN 'ecuador'
        WHEN 'United States' THEN 'estados unidos'
        WHEN 'Panama'        THEN 'panama'
        ELSE LOWER(es.country)
    END AS pais,
    bu.consolidated_business_unit_name AS empresa,
    NULLIF(LOWER(es.structure), '-1') AS structure,
    UPPER(es.cost_center_code) AS numero_centro_de_custo,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    LOWER(es.job_name) AS cargo,
    es.band AS banda,
    LOWER(es.job_family) AS classe_cargo,
    job.working_hours_regime AS working_hours_regime,
    job.workload AS workload,
    LOWER(es.manager_name) AS gestor,
    LOWER(es.name_l1) AS l1_gestor,
    LOWER(es.name_l2) AS l2_gestor,
    LOWER(es.name_l3) AS l3_gestor,
    CASE
        WHEN es.amount_salary IS NULL OR CAST(es.amount_salary AS DOUBLE) < 1 THEN NULL
        ELSE CAST(CAST(es.amount_salary AS DECIMAL(10, 2)) AS STRING)
    END AS salario,
    CASE LOWER(es.registered_sex)
        WHEN 'male' THEN 'masculino'
        WHEN 'female' THEN 'feminino'
        WHEN 'masculino' THEN 'masculino'
        WHEN 'feminino' THEN 'feminino'
        ELSE LOWER(es.registered_sex)
    END AS sexo,
    LOWER(es.address_city) AS residencia_cidade,
    LOWER(es.address_state) AS residencia_uf,
    es.dt_birth AS dt_nascimento,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
LEFT JOIN
    dw_compensation.dim_job AS job
        ON job.sk_job_version = es.sk_job_version
WHERE
    es.is_current_for_employee = TRUE
ORDER BY
    status,
    dt_desligamento DESC,
    dt_inicio DESC
