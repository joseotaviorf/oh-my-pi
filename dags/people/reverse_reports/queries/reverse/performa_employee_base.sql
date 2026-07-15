-- Full employee roster exported quarterly to Google Sheets for the Performa performance objectives dashboard.
WITH
email_map AS (
    SELECT DISTINCT
        LOWER(es.assignment_number) AS assignment_number,
        LOWER(es.work_email) AS work_email
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND es.work_email IS NOT NULL
        AND LOWER(es.work_email) NOT LIKE '%@quinto.com%'
),
hierarchy AS (
    SELECT
        es.*,
        CASE
            WHEN LOWER(es.assignment_number_l1) = LOWER(es.assignment_number) THEN NULL
            ELSE LOWER(es.assignment_number_l1)
        END AS hierarchy_l1,
        CASE
            WHEN LOWER(es.assignment_number_l2) = LOWER(es.assignment_number) THEN NULL
            ELSE LOWER(es.assignment_number_l2)
        END AS hierarchy_l2,
        CASE
            WHEN LOWER(es.assignment_number_l3) = LOWER(es.assignment_number) THEN NULL
            ELSE LOWER(es.assignment_number_l3)
        END AS hierarchy_l3,
        CASE
            WHEN LOWER(es.assignment_number_l4) = LOWER(es.assignment_number) THEN NULL
            ELSE LOWER(es.assignment_number_l4)
        END AS hierarchy_l4,
        CASE
            WHEN LOWER(es.assignment_number_l5) = LOWER(es.assignment_number) THEN NULL
            ELSE LOWER(es.assignment_number_l5)
        END AS hierarchy_l5,
        CASE
            WHEN LOWER(es.assignment_number_l6) = LOWER(es.assignment_number) THEN NULL
            ELSE LOWER(es.assignment_number_l6)
        END AS hierarchy_l6,
        CASE
            WHEN LOWER(es.assignment_number_l7) = LOWER(es.assignment_number) THEN NULL
            ELSE LOWER(es.assignment_number_l7)
        END AS hierarchy_l7,
        CASE
            WHEN LOWER(es.assignment_number_l8) = LOWER(es.assignment_number) THEN NULL
            ELSE LOWER(es.assignment_number_l8)
        END AS hierarchy_l8,
        CASE
            WHEN LOWER(es.assignment_number_l9) = LOWER(es.assignment_number) THEN NULL
            ELSE LOWER(es.assignment_number_l9)
        END AS hierarchy_l9
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND (
            es.dt_terminated IS NULL
            OR es.dt_terminated > DATE('2023-12-31')
        )
),
hierarchy_emails AS (
    SELECT
        h.*,
        'gbraga@quintoandar.com.br' AS id_l0,
        e1.work_email AS id_l1,
        e2.work_email AS id_l2,
        e3.work_email AS id_l3,
        e4.work_email AS id_l4,
        e5.work_email AS id_l5,
        e6.work_email AS id_l6,
        e7.work_email AS id_l7,
        e8.work_email AS id_l8,
        e9.work_email AS id_l9
    FROM
        hierarchy AS h
    LEFT JOIN
        email_map AS e1
            ON h.hierarchy_l1 = e1.assignment_number
    LEFT JOIN
        email_map AS e2
            ON h.hierarchy_l2 = e2.assignment_number
    LEFT JOIN
        email_map AS e3
            ON h.hierarchy_l3 = e3.assignment_number
    LEFT JOIN
        email_map AS e4
            ON h.hierarchy_l4 = e4.assignment_number
    LEFT JOIN
        email_map AS e5
            ON h.hierarchy_l5 = e5.assignment_number
    LEFT JOIN
        email_map AS e6
            ON h.hierarchy_l6 = e6.assignment_number
    LEFT JOIN
        email_map AS e7
            ON h.hierarchy_l7 = e7.assignment_number
    LEFT JOIN
        email_map AS e8
            ON h.hierarchy_l8 = e8.assignment_number
    LEFT JOIN
        email_map AS e9
            ON h.hierarchy_l9 = e9.assignment_number
),
employee_access AS (
    SELECT
        he.sk_business_unit,
        he.sk_cost_center_version,
        he.name,
        he.person_number,
        he.work_email,
        he.status,
        he.band,
        he.manager_assignment_number,
        he.manager_name,
        he.manager_work_email,
        he.job_name,
        he.job_family,
        he.cost_center_code,
        he.cost_center_name,
        he.owner_l1_name,
        he.owner_l2_name,
        he.owner_l3_name,
        he.vertical,
        he.structure,
        he.team,
        he.business,
        he.product,
        he.brand,
        he.chapter,
        he.line,
        he.hrbp_work_email,
        he.is_manager,
        he.dt_original_hire,
        he.dt_terminated,
        he.termination_category,
        he.employment_type,
        he.cpf,
        he.country,
        he.business_unit_name,
        he.name_l1,
        he.name_l2,
        he.name_l3,
        he.name_l4,
        he.name_l5,
        he.name_l6,
        CONCAT(
            '-',
            LOWER(he.work_email),
            '-',
            CASE
                WHEN he.id_l1 IS NULL OR LOWER(he.work_email) = he.id_l1 THEN he.id_l0
                WHEN he.id_l2 IS NULL OR LOWER(he.work_email) = he.id_l2 THEN CONCAT_WS('-', he.id_l0, he.id_l1)
                WHEN he.id_l3 IS NULL OR LOWER(he.work_email) = he.id_l3 THEN CONCAT_WS('-', he.id_l0, he.id_l1, he.id_l2)
                WHEN he.id_l4 IS NULL OR LOWER(he.work_email) = he.id_l4 THEN CONCAT_WS('-', he.id_l0, he.id_l1, he.id_l2, he.id_l3)
                WHEN he.id_l5 IS NULL OR LOWER(he.work_email) = he.id_l5 THEN CONCAT_WS('-', he.id_l0, he.id_l1, he.id_l2, he.id_l3, he.id_l4)
                WHEN he.id_l6 IS NULL OR LOWER(he.work_email) = he.id_l6 THEN CONCAT_WS('-', he.id_l0, he.id_l1, he.id_l2, he.id_l3, he.id_l4, he.id_l5)
                WHEN he.id_l7 IS NULL OR LOWER(he.work_email) = he.id_l7 THEN CONCAT_WS('-', he.id_l0, he.id_l1, he.id_l2, he.id_l3, he.id_l4, he.id_l5, he.id_l6)
                WHEN he.id_l8 IS NULL OR LOWER(he.work_email) = he.id_l8 THEN CONCAT_WS('-', he.id_l0, he.id_l1, he.id_l2, he.id_l3, he.id_l4, he.id_l5, he.id_l6, he.id_l7)
                WHEN he.id_l9 IS NULL OR LOWER(he.work_email) = he.id_l9 THEN CONCAT_WS('-', he.id_l0, he.id_l1, he.id_l2, he.id_l3, he.id_l4, he.id_l5, he.id_l6, he.id_l7, he.id_l8)
                ELSE CONCAT_WS('-', he.id_l0, he.id_l1, he.id_l2, he.id_l3, he.id_l4, he.id_l5, he.id_l6, he.id_l7, he.id_l8, he.id_l9)
            END,
            '-'
        ) AS access_list
    FROM
        hierarchy_emails AS he
)
SELECT
    q.quarter,
    bu.consolidated_business_unit_name AS empresa,
    es.name AS nome,
    es.person_number AS matricula,
    LOWER(es.work_email) AS email_pin,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    LOWER(es.band) AS banda,
    LOWER(es.manager_assignment_number) AS id_gestor,
    es.manager_name AS gestor,
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
    CASE WHEN es.is_manager IS TRUE THEN 1 ELSE 0 END AS fl_lider,
    es.dt_original_hire AS dt_inicio,
    es.dt_terminated AS dt_desligamento,
    CASE
        WHEN es.termination_category IS NULL THEN NULL
        WHEN LOWER(es.termination_category) LIKE '%involunt%' THEN 'involuntario'
        WHEN LOWER(es.termination_category) LIKE '%volunt%' THEN 'voluntario'
        WHEN LOWER(es.termination_category) LIKE '%falec%' THEN 'falecimento'
        ELSE LOWER(es.termination_category)
    END AS motivo_desligamento,
    CASE LOWER(es.employment_type)
        WHEN 'young apprentice' THEN 'jovem aprendiz'
        WHEN 'intern' THEN 'estagiario'
        WHEN 'clt' THEN 'clt'
        ELSE LOWER(es.employment_type)
    END AS vinculo,
    es.cpf,
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
    es.business_unit_name AS marca_produto_dedicado,
    LOWER(es.name_l1) AS l1_gestor,
    LOWER(es.name_l2) AS l2_gestor,
    LOWER(es.name_l3) AS l3_gestor,
    LOWER(es.name_l4) AS l4_gestor,
    LOWER(es.name_l5) AS l5_gestor,
    LOWER(es.name_l6) AS l6_gestor,
    es.access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    employee_access AS es
CROSS JOIN (
    SELECT 'Q1' AS quarter
    UNION ALL SELECT 'Q2'
    UNION ALL SELECT 'Q3'
    UNION ALL SELECT 'Q4'
) AS q
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
ORDER BY
    bu.consolidated_business_unit_name,
    es.name
