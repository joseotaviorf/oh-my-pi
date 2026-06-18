SELECT
    bu.consolidated_business_unit_name AS empresa,
    es.name AS nome,
    es.dt_hired AS dt_inicio,
    es.dt_terminated AS dt_desligamento,
    LOWER(es.work_email) AS email,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    es.band AS banda,
    mh.name_l1 AS gestor,
    es.job_name AS cargo,
    LOWER(es.cost_center_code) AS numero_centro_de_custo,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    CASE
        WHEN es.is_manager IS TRUE THEN 1
        ELSE 0
    END AS fl_lider,
    es.dt_birth AS dt_nascimento,
    CAST(FROM_UTC_TIMESTAMP(es.ts_load, 'America/Sao_Paulo') AS DATE) AS dt_last_update,
    LOWER(es.hrbp_work_email) AS hrbp,
    es.months_tenure_in_company AS idade_empresa,
    NULLIF(LOWER(es.business), '-1') AS business,
    NULLIF(LOWER(es.product), '-1') AS product,
    mh.name_l0 AS l0_gestor,
    mh.name_l1 AS l1_gestor,
    mh.name_l2 AS l2_gestor,
    mh.name_l3 AS l3_gestor,
    mh.name_l4 AS l4_gestor,
    mh.name_l5 AS l5_gestor,
    mh.name_l6 AS l6_gestor,
    mh.name_l7 AS l7_gestor,
    mh.name_l8 AS l8_gestor,
    LOWER(es.ethnicity) AS raca,
    LOWER(es.sexual_orientation) AS orientacao_sexual,
    LOWER(es.gender_identity) AS identidade_genero,
    LOWER(es.registered_sex) AS sexo,
    LOWER(es.religion) AS religiosidade,
    LOWER(es.documented_disability_name) AS pcd_laudo,
    LOWER(es.neurodiversity) AS neurodiversidade,
    LOWER(es.country) AS pais,
    NULLIF(es.owner_l1_name, '-1') AS l1_cc,
    NULLIF(es.owner_l2_name, '-1') AS l2_cc,
    NULLIF(es.owner_l3_name, '-1') AS l3_cc,
    NULLIF(LOWER(es.structure), '-1') AS structure,
    NULLIF(LOWER(es.vertical), '-1') AS vertical,
    NULLIF(LOWER(es.team), '-1') AS team,
    NULLIF(LOWER(es.brand), '-1') AS brand,
    NULLIF(LOWER(es.chapter), '-1') AS chapter,
    NULLIF(LOWER(es.line), '-1') AS line,
    es.dt_original_hire AS dt_inicio_person,
    CASE
        WHEN LOWER(es.ethnicity) IN ('branca', 'amarela') THEN 'Non-BIM'
        WHEN LOWER(es.ethnicity) = '-' THEN 'N/A'
        WHEN LOWER(es.ethnicity) IN ('preta', 'parda', 'indigena') THEN 'BIM'
        ELSE 'N/A'
    END AS bim,
    CASE
        WHEN LOWER(es.gender_identity) IN (
            'mulher transgenero',
            'mulher cis',
            'mujer cisgenero (cis)',
            'mulher cisgenero',
            'cisgender woman',
            'mulher trans ou travesti'
        ) THEN 'Women'
        WHEN LOWER(es.gender_identity) IN (
            'homem cis',
            'hombre cisgenero (cis)',
            'homem cisgenero',
            'homem transgenero',
            'homemtrans',
            'cisgender man'
        ) THEN 'Non-Women'
        WHEN LOWER(es.gender_identity) IN (
            'genero nao-binaria',
            'genero fluido',
            'outro',
            'demi-genero',
            'nao-binario',
            'homem trans nao-binario'
        ) THEN 'Other'
        WHEN LOWER(es.gender_identity) = '-' THEN 'N/A'
        WHEN LOWER(es.gender_identity) = 'prefiro nao informar' THEN 'Prefiro não informar'
        ELSE 'N/A'
    END AS women,
    CASE
        WHEN LOWER(es.sexual_orientation) IN (
            '1 - assexual',
            '2 - bissexual',
            '5 - pansexual',
            '4 - homossexual',
            '6 - outro'
        )
        OR LOWER(es.gender_identity) IN (
            'genero fluido',
            'genero nao-binaria',
            'homem transgenero',
            'mulher transgenero',
            'outro',
            'demi-genero',
            'mulher trans ou travesti',
            'nao-binario',
            'homemtrans',
            'homem trans nao-binario'
        ) THEN 'LGBT+'
        WHEN LOWER(es.sexual_orientation) = '3 - heterossexual' THEN 'Non-LGBT+'
        WHEN LOWER(es.sexual_orientation) = 'prefiro nao informar'
            OR LOWER(es.gender_identity) = 'prefiro nao informar' THEN 'Prefiro não informar'
        WHEN LOWER(es.sexual_orientation) = '-'
            OR LOWER(es.gender_identity) = '-' THEN 'N/A'
        ELSE 'N/A'
    END AS lgbt,
    NULLIF(dis.documented_name, '-1') AS com_laudo,
    COALESCE(
        NULLIF(dis.self_declared_name, '-1'),
        NULLIF(dis.documented_name, '-1')
    ) AS auto_declarado,
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
    dw_demographics.dim_employee_disability AS dis
        ON dis.sk_employee = es.sk_employee
        AND dis.is_primary = TRUE
        AND CURRENT_DATE() >= dis.dt_valid_from
        AND CURRENT_DATE() <= dis.dt_valid_to
WHERE
    es.dt_reference = CURRENT_DATE()
    AND es.is_primary_assignment_for_snapshot = TRUE
