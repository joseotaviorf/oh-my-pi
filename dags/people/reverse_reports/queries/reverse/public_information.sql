-- Migration of the base_public_no_banda cell from the external_reports notebook.
-- Source: datalake_people_analytics_sandbox.base_completa_hierarquia (deprecated)
-- Replacement: DW 2.0 tables; active-only filter.
WITH
    dt_inicio_person AS (
        SELECT
            empl.person_number,
            MIN(snap.dt_hired) AS dt_inicio_person
        FROM
            dw_employee_details.fact_assignment_snapshots AS snap
        LEFT JOIN
            dw_employee_details.dim_employee AS empl
                ON snap.sk_employee = empl.sk_employee
        WHERE
            empl.person_number IS NOT NULL
        GROUP BY
            empl.person_number
    )
SELECT
    e.person_number AS matricula,
    CASE
        WHEN bu.business_unit_name = 'Deel - QuintoAndar' THEN 'QuintoAndar SP'
        WHEN bu.business_unit_name IN (
            'Classifieds Latam',
            'OneLoop S.R.L.',
            'Grupo Navent S.R.L.',
            'Dridco S.A.U.',
            'SOLUSER SOLUCIONES Y SERVICIOS SA DE CV',
            'DRIDCO MEXICO SA DE CV',
            'TECNOLOGÍA PARA INMOBILIARIAS SA DE CV'
        ) THEN 'Classifieds'
        WHEN bu.business_unit_name = 'Atta' THEN 'ATTA'
        WHEN bu.business_unit_name = 'Benvi MX' THEN 'Benvi México'
        WHEN bu.business_unit_name = 'Benvi PT' THEN 'QuintoAndar Portugal'
        ELSE bu.business_unit_name
    END AS empresa,
    LOWER(TRIM(e.name)) AS nome,
    LOWER(e.work_email) AS email,
    'ativo' AS status,
    LOWER(TRIM(mng_emp.name)) AS gestor,
    LOWER(TRIM(j.job_name)) AS cargo,
    LOWER(cc.cost_center_code) AS numero_centro_de_custo,
    CONCAT(
        LOWER(cc.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(cc.cost_center_name), 10)
    ) AS centro_de_custo,
    NULLIF(LOWER(cc.owner_l1_name), '-1') AS l1_cc,
    NULLIF(LOWER(cc.owner_l2_name), '-1') AS l2_cc,
    NULLIF(LOWER(cc.owner_l3_name), '-1') AS l3_cc,
    NULLIF(LOWER(cc.vertical), '-1') AS vertical,
    NULLIF(LOWER(cc.structure), '-1') AS structure,
    NULLIF(LOWER(cc.team), '-1') AS team,
    NULLIF(LOWER(cc.business), '-1') AS business,
    NULLIF(LOWER(cc.product), '-1') AS product,
    NULLIF(LOWER(cc.brand), '-1') AS brand,
    NULLIF(LOWER(cc.chapter), '-1') AS chapter,
    NULLIF(LOWER(cc.line), '-1') AS line,
    LOWER(cc.hrbp_work_email) AS hrbp,
    CASE
        WHEN bu.business_unit_name IN (
            'OneLoop S.R.L.',
            'Grupo Navent S.R.L.',
            'Dridco S.A.U.'
        ) THEN 'argentina'
        WHEN bu.business_unit_name IN (
            'SOLUSER SOLUCIONES Y SERVICIOS SA DE CV',
            'TECNOLOGÍA PARA INMOBILIARIAS SA DE CV',
            'DRIDCO MEXICO SA DE CV',
            'Benvi MX'
        ) THEN 'mexico'
        WHEN bu.business_unit_name = 'Benvi PT' THEN 'portugal'
        WHEN bu.business_unit_name IN ('Deel - QuintoAndar', 'MLSP')
            OR bu.business_unit_name ILIKE 'quintoandar __' THEN 'brasil'
        ELSE LOWER(j.country)
    END AS pais,
    LOWER(c.address_state) AS residencia_uf,
    LOWER(c.address_city) AS residencia_cidade,
    LOWER(TRIM(COALESCE(h.name_l0, 'gabriel braga vieira'))) AS l0_gestor,
    LOWER(TRIM(h.name_l1)) AS l1_gestor,
    LOWER(TRIM(h.name_l2)) AS l2_gestor,
    LOWER(TRIM(h.name_l3)) AS l3_gestor,
    LOWER(TRIM(h.name_l4)) AS l4_gestor,
    LOWER(TRIM(h.name_l5)) AS l5_gestor,
    LOWER(TRIM(h.name_l6)) AS l6_gestor,
    LOWER(TRIM(h.name_l7)) AS l7_gestor,
    LOWER(TRIM(h.name_l8)) AS l8_gestor,
    f.months_tenure_in_company AS idade_empresa,
    CASE
        WHEN f.is_manager IS TRUE THEN 1
        ELSE 0
    END AS fl_lider,
    f.dt_hired AS dt_inicio,
    CAST(FROM_UTC_TIMESTAMP(f.ts_load, 'America/Sao_Paulo') AS DATE) AS dt_last_update,
    dip.dt_inicio_person AS dt_inicio_person,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    dw_employee_details.fact_assignment_snapshots AS f
LEFT JOIN
    dw_employee_details.dim_employee AS e
        ON f.sk_employee = e.sk_employee
LEFT JOIN
    dw_employee_details.dim_contact AS c
        ON f.sk_contact_version = c.sk_contact_version
LEFT JOIN
    dw_compensation.dim_job AS j
        ON f.sk_job_version = j.sk_job_version
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON f.sk_cost_center_version = cc.sk_cost_center_version
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON f.sk_business_unit = bu.sk_business_unit
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS h
        ON f.sk_hierarchy_version = h.sk_hierarchy_version
LEFT JOIN
    dw_employee_details.fact_assignment_snapshots AS mng_snap
        ON mng_snap.assignment_number = h.manager_assignment_number
        AND mng_snap.is_current = TRUE
LEFT JOIN
    dw_employee_details.dim_employee AS mng_emp
        ON mng_emp.sk_employee = mng_snap.sk_employee
LEFT JOIN
    dt_inicio_person AS dip
        ON dip.person_number = e.person_number
WHERE
    f.is_current = TRUE
    AND f.is_primary_assignment_for_snapshot = TRUE
    AND (f.dt_terminated IS NULL OR f.dt_terminated >= CURRENT_DATE())
    AND f.dt_hired <= CURRENT_DATE()
    AND (LOWER(e.work_email) NOT LIKE '%@ext.%' OR e.work_email IS NULL)
ORDER BY
    e.name
