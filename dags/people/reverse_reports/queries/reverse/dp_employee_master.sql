SELECT
    es.person_number AS person_number,
    es.assignment_number AS assignment_number,
    bu.consolidated_business_unit_name AS empresa,
    es.name AS nome,
    es.cpf,
    es.dt_hired AS dt_inicio,
    es.dt_terminated AS dt_desligamento,
    LOWER(es.work_email) AS email,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    mh.name_l1 AS gestor,
    es.job_name AS cargo,
    es.job_family AS classe_cargo,
    es.band AS banda,
    LOWER(es.cost_center_code) AS numero_centro_de_custo,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    NULLIF(es.owner_l1_name, '-1') AS l1_cc,
    NULLIF(es.owner_l2_name, '-1') AS l2_cc,
    NULLIF(es.owner_l3_name, '-1') AS l3_cc,
    NULLIF(LOWER(es.vertical), '-1') AS vertical,
    NULLIF(LOWER(es.structure), '-1') AS structure,
    NULLIF(LOWER(es.team), '-1') AS team,
    NULLIF(LOWER(es.business), '-1') AS business,
    NULLIF(LOWER(es.product), '-1') AS product,
    NULLIF(LOWER(es.brand), '-1') AS brand,
    NULLIF(LOWER(es.chapter), '-1') AS chapter,
    NULLIF(LOWER(es.line), '-1') AS line,
    CASE
        WHEN es.is_manager IS TRUE THEN 1
        ELSE 0
    END AS fl_lider,
    es.dt_birth AS dt_nascimento,
    CAST(FROM_UTC_TIMESTAMP(es.ts_load, 'America/Sao_Paulo') AS DATE) AS dt_last_update,
    LOWER(es.hrbp_work_email) AS hrbp,
    es.months_tenure_in_company AS idade_empresa,
    mh.name_l0 AS l0_gestor,
    mh.name_l1 AS l1_gestor,
    mh.name_l2 AS l2_gestor,
    mh.name_l3 AS l3_gestor,
    mh.name_l4 AS l4_gestor,
    mh.name_l5 AS l5_gestor,
    mh.name_l6 AS l6_gestor,
    mh.name_l7 AS l7_gestor,
    mh.name_l8 AS l8_gestor,
    es.rg,
    LOWER(es.registered_sex) AS sexo,
    es.full_phone_number AS numero_celular,
    LOWER(es.personal_email) AS email_pessoal,
    LOWER(es.address_street) AS residencia_endereco,
    es.address_number AS residencia_numero,
    LOWER(es.address_complement) AS residencia_complemento,
    es.address_zip_code AS residencia_cep,
    LOWER(es.address_city) AS residencia_cidade,
    LOWER(es.address_state) AS residencia_uf,
    CAST(NULL AS STRING) AS sub_diretoria_depara,
    doc.mother_name AS nome_da_mae,
    de.employee_tmf_code AS matricula_tmf,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS mh
        ON mh.assignment_number = es.assignment_number
        AND mh.is_current = TRUE
LEFT JOIN
    dw_employee_details.dim_documentation AS doc
        ON doc.sk_documentation_version = es.sk_documentation_version
LEFT JOIN
    dw_employee_details.dim_employee AS de
        ON de.sk_employee = es.sk_employee
WHERE
    es.dt_reference = CURRENT_DATE()
    AND es.is_primary_assignment_for_snapshot = TRUE
