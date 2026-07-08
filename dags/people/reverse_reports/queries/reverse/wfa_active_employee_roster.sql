SELECT
    bu.consolidated_business_unit_name AS empresa,
    es.name AS nome,
    es.person_number AS matricula,
    LOWER(es.work_email) AS email,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    es.band AS banda,
    es.manager_assignment_number AS id_gestor,
    es.manager_name AS gestor,
    LOWER(es.manager_work_email) AS email_gestor,
    es.job_name AS cargo,
    es.job_family AS classe_cargo,
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
    LOWER(es.hrbp_work_email) AS hrbp,
    CASE
        WHEN es.is_manager IS TRUE THEN 1
        ELSE 0
    END AS fl_lider,
    es.dt_hired AS dt_inicio,
    es.dt_terminated AS dt_desligamento,
    es.termination_reason_name AS motivo_desligamento,
    LOWER(es.employment_type) AS vinculo,
    es.cpf,
    CAST(FROM_UTC_TIMESTAMP(es.ts_load, 'America/Sao_Paulo') AS DATE) AS dt_last_update,
    CAST(NULL AS STRING) AS marca_produto_dedicado,
    LOWER(es.cost_center_code) AS numero_centro_de_custo,
    LOWER(es.address_state) AS residencia_uf,
    LOWER(es.address_city) AS residencia_cidade,
    LOWER(es.country) AS pais,
    es.dt_birth AS dt_nascimento,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
WHERE
    es.is_current_for_employee = TRUE
    AND LOWER(es.status) = 'active'
