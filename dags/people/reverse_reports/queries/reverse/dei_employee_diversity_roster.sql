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
    CASE WHEN dis.is_active = TRUE THEN 'sim' ELSE 'nao' END AS pcd_laudo,
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
        WHEN LOWER(es.ethnicity) IN ('white', 'asian') THEN 'Non-BIM'
        WHEN LOWER(es.ethnicity) IN (
            'black or african american',
            'two or more races',
            'american indian',
            'desativado black or african american'
        ) THEN 'BIM'
        ELSE 'N/A'
    END AS bim,
    CASE
        WHEN LOWER(es.gender_identity) IN ('woman cisgender', 'woman transgender') THEN 'Women'
        WHEN LOWER(es.gender_identity) IN ('man cisgender', 'man transgender') THEN 'Non-Women'
        WHEN LOWER(es.gender_identity) IN ('non binary', 'other') THEN 'Other'
        WHEN LOWER(es.gender_identity) = 'prefer not to say' THEN 'Prefiro não informar'
        ELSE 'N/A'
    END AS women,
    CASE
        WHEN LOWER(es.sexual_orientation) IN ('homosexual', 'bisexual', 'pansexual', 'asexual', 'other')
            OR LOWER(es.gender_identity) IN ('woman transgender', 'man transgender', 'non binary', 'other') THEN 'LGBT+'
        WHEN LOWER(es.sexual_orientation) = 'heterosexual' THEN 'Non-LGBT+'
        WHEN LOWER(es.sexual_orientation) LIKE '%rather not answer%'
            OR LOWER(es.gender_identity) = 'prefer not to say' THEN 'Prefiro não informar'
        WHEN es.sexual_orientation = '-1'
            OR es.gender_identity = '-1' THEN 'N/A'
        ELSE 'N/A'
    END AS lgbt,
    CASE dis.category
        WHEN 'Motor Deficiency' THEN 'Deficiência física'
        WHEN 'Visual impairment' THEN 'Deficiência visual'
        WHEN 'Hearing impairment' THEN 'Deficiência auditiva'
        WHEN 'Mental disorder' THEN 'Deficiência mental/psicossocial'
        WHEN 'Intellectual disability' THEN 'Deficiência intelectual'
        WHEN 'Múltiplo' THEN 'Múltiplas'
    END AS com_laudo,
    COALESCE(
        CASE dis.self_declared_name
            WHEN '2' THEN 'Deficiência auditiva'
            WHEN '3' THEN 'Deficiência física'
            WHEN '4' THEN 'Deficiência intelectual'
            WHEN '5' THEN 'Deficiência visual'
            WHEN '6' THEN 'Deficiência mental/psicossocial'
            WHEN '7' THEN 'Múltiplas'
            WHEN '8' THEN 'Outra'
        END,
        CASE dis.category
            WHEN 'Motor Deficiency' THEN 'Deficiência física'
            WHEN 'Visual impairment' THEN 'Deficiência visual'
            WHEN 'Hearing impairment' THEN 'Deficiência auditiva'
            WHEN 'Mental disorder' THEN 'Deficiência mental/psicossocial'
            WHEN 'Intellectual disability' THEN 'Deficiência intelectual'
            WHEN 'Múltiplo' THEN 'Múltiplas'
        END
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
    es.is_current_for_employee = TRUE
