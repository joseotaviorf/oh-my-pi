-- Full compensation base export for the Compensation team Google Sheet (legacy people_reports base_compensation view).
WITH
current_assignment AS (
    SELECT
        fas.assignment_number,
        fas.sk_compensation_version
    FROM
        dw_employee_details.fact_assignment_snapshots AS fas
    WHERE
        fas.is_current_for_employee = TRUE
)
SELECT
    es.assignment_number AS id_colaborador,
    bu.consolidated_business_unit_name AS empresa,
    LOWER(es.name) AS nome,
    LOWER(es.work_email) AS email,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    es.termination_reason_name AS motivo_desligamento,
    LOWER(es.manager_name) AS gestor,
    LOWER(es.band) AS banda,
    CASE es.country
        WHEN 'Brazil' THEN 'brasil'
        WHEN 'Argentina' THEN 'argentina'
        WHEN 'Mexico' THEN 'mexico'
        WHEN 'Portugal' THEN 'portugal'
        WHEN 'Peru' THEN 'peru'
        WHEN 'Uruguay' THEN 'uruguai'
        WHEN 'Ecuador' THEN 'ecuador'
        WHEN 'United States' THEN 'estados unidos'
        WHEN 'Panama' THEN 'panama'
        ELSE LOWER(es.country)
    END AS pais,
    LOWER(es.job_name) AS cargo,
    LOWER(es.job_family) AS classe_cargo,
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
    LOWER(es.personal_email) AS email_pessoal,
    es.dt_employee_hired AS dt_inicio,
    es.dt_terminated AS dt_desligamento,
    es.cpf,
    CASE
        WHEN LOWER(org_job.career_track) = 'contribuidor individual' THEN 'ci'
        WHEN LOWER(org_job.career_track) IN ('líder', 'lider') THEN 'l'
        ELSE NULL
    END AS trilha,
    CAST(FROM_UTC_TIMESTAMP(es.ts_load, 'America/Sao_Paulo') AS DATE) AS dt_last_update,
    CASE
        WHEN es.amount_salary IS NULL OR CAST(es.amount_salary AS DOUBLE) < 1 THEN CAST(NULL AS STRING)
        ELSE CAST(CAST(es.amount_salary AS DECIMAL(10, 2)) AS STRING)
    END AS salario,
    CASE
        WHEN
            fc.currency_code IS NOT NULL
            AND fc.currency_code <> 'BRL'
            AND fc.amount_salary IS NOT NULL
            THEN CONCAT(fc.currency_code, ' ', CAST(fc.amount_salary AS STRING))
        ELSE CAST(NULL AS STRING)
    END AS salario_moeda_local,
    NULLIF(
        CASE
            WHEN comp_job.target_plr_salary_multiplier > 0
            THEN CAST(comp_job.target_plr_salary_multiplier AS DOUBLE)
            ELSE CAST(comp_job.target_plr AS DOUBLE)
        END,
        0
    ) AS target_rv,
    LOWER(comp_job.salary_table) AS tabela_salarial,
    LOWER(es.name_l1) AS l1_gestor,
    LOWER(es.name_l2) AS l2_gestor,
    LOWER(es.name_l3) AS l3_gestor,
    LOWER(es.name_l4) AS l4_gestor,
    LOWER(es.hrbp_work_email) AS hrbp,
    es.marital_status AS estado_civil,
    es.salary_midpoint_ratio AS pos_faixa,
    CAST(comp_job.salary_range_mid AS DOUBLE) AS referencia,
    es.business_unit_name AS business_unit_name,
    es.dt_assignment_started AS dt_admissao_assignment,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
LEFT JOIN
    current_assignment AS ca
        ON ca.assignment_number = es.assignment_number
LEFT JOIN
    dw_compensation.fact_compensations AS fc
        ON fc.sk_compensation = ca.sk_compensation_version
        AND ca.sk_compensation_version <> '-1'
LEFT JOIN
    dw_compensation.dim_job AS comp_job
        ON comp_job.sk_job_version = es.sk_job_version
LEFT JOIN
    dw_organization.dim_job AS org_job
        ON comp_job.id_job = org_job.sk_job
WHERE
    es.is_current_for_employee = TRUE
