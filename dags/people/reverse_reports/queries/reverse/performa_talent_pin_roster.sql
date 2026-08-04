-- Full employee roster for the Performa & Talent PIN dashboard (api_PIN_adquiridas tab).
SELECT
    bu.consolidated_business_unit_name AS empresa,
    LOWER(es.name) AS nome,
    es.person_number AS matricula,
    LOWER(es.work_email) AS email,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    es.band AS banda,
    LOWER(es.manager_assignment_number) AS id_gestor,
    LOWER(es.manager_name) AS gestor,
    LOWER(es.manager_work_email) AS email_gestor,
    LOWER(es.job_name) AS cargo,
    LOWER(es.job_family) AS classe_cargo,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    NULLIF(LOWER(es.owner_l1_name), '-1') AS l1_cc,
    NULLIF(LOWER(es.owner_l2_name), '-1') AS l2_cc,
    NULLIF(LOWER(es.owner_l3_name), '-1') AS l3_cc,
    NULLIF(LOWER(es.vertical), '-1') AS vertical,
    NULLIF(LOWER(es.structure), '-1') AS structure,
    NULLIF(LOWER(es.team), '-1') AS team,
    NULLIF(LOWER(es.business), '-1') AS business,
    NULLIF(LOWER(es.product), '-1') AS product,
    NULLIF(LOWER(es.brand), '-1') AS brand,
    NULLIF(LOWER(es.chapter), '-1') AS chapter,
    NULLIF(LOWER(es.line), '-1') AS line,
    LOWER(COALESCE(es.hrbp_work_email, cc_current.hrbp_work_email)) AS hrbp,
    CASE
        WHEN es.is_manager IS TRUE THEN 1
        ELSE 0
    END AS fl_lider,
    es.dt_employee_hired AS dt_inicio,
    es.dt_terminated AS dt_desligamento,
    CASE
        WHEN LOWER(es.termination_type) = 'voluntary' THEN 'voluntario'
        WHEN LOWER(es.termination_type) = 'involuntary' THEN 'involuntario'
        ELSE LOWER(es.termination_type)
    END AS motivo_desligamento,
    CASE LOWER(es.employment_type)
        WHEN 'young apprentice' THEN 'jovem aprendiz'
        WHEN 'intern' THEN 'estagiario'
        WHEN 'clt' THEN 'clt'
        ELSE LOWER(es.employment_type)
    END AS vinculo,
    COALESCE(es.cpf, doc.cpf) AS cpf,
    CAST(FROM_UTC_TIMESTAMP(es.ts_load, 'America/Sao_Paulo') AS DATE) AS dt_last_update,
    es.business_unit_name AS marca_produto_dedicado,
    CASE
        WHEN LOWER(es.gender_identity) IN (
            'man cisgender',
            'man transgender',
            'cisgender man',
            'hombre cisgenero (cis)',
            'homem cis',
            'homem cisgenero',
            'homem transgenero',
            'homemtrans'
        ) THEN 'homem'
        WHEN LOWER(es.gender_identity) IN (
            'woman cisgender',
            'woman transgender',
            'cisgender woman',
            'mujer cisgenero (cis)',
            'mulher cis',
            'mulher cisgenero',
            'mulher trans ou travesti',
            'mulher transgenero'
        ) THEN 'mulher'
        WHEN LOWER(es.registered_sex) IN ('masculino', 'male') THEN 'homem'
        WHEN LOWER(es.registered_sex) IN ('feminino', 'female') THEN 'mulher'
    END AS genero,
    LOWER(es.name_l1) AS l1_gestor,
    LOWER(es.name_l2) AS l2_gestor,
    LOWER(es.name_l3) AS l3_gestor,
    LOWER(es.name_l4) AS l4_gestor,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON cc.sk_cost_center_version = es.sk_cost_center_version
LEFT JOIN
    dw_organization.dim_cost_center AS cc_current
        ON cc_current.id_organization = cc.id_organization
        AND cc_current.is_current = TRUE
LEFT JOIN
    dw_employee_details.dim_documentation AS doc
        ON doc.person_number = es.person_number
        AND doc.is_current = TRUE
WHERE
    es.is_current_for_employee = TRUE
