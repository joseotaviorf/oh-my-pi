-- License to Hire dashboard base: eligible employees and Degreed pathway completion.
-- Exception: learning progress comes from enrich `datalake_learning.*` — no `dw_learning` yet (DBP-1736).
WITH load_timestamp AS (
    SELECT
        MAX(ac.ts_load) AS ts_load_max
    FROM
        datalake_learning.all_completions AS ac
    WHERE
        ac.id_pathway IN ('QQRXj', 'k4PR7', 'L6Wb7', 'y08qk', 'pRNgy', 'RjgQ5')
        AND ac.learning_object_type = 'Pathway'
),
eligible_employees AS (
    SELECT
        es.person_number AS person_number,
        es.name AS employee_name,
        LOWER(es.work_email) AS email,
        es.band AS band,
        es.job_name AS job_name,
        es.dt_employee_hired AS dt_hired,
        CASE
            WHEN es.is_manager IS TRUE THEN 1
            ELSE 0
        END AS is_leader_flag,
        NULLIF(LOWER(es.vertical), '-1') AS vertical,
        LOWER(es.manager_work_email) AS manager_email,
        LOWER(es.hrbp_work_email) AS hrbp,
        es.manager_name AS manager_name,
        LOWER(es.country) AS country,
        NULLIF(LOWER(es.product), '-1') AS dedicated_product_brand,
        es.months_employee_tenure AS company_tenure_months,
        NULLIF(LOWER(es.structure), '-1') AS structure,
        NULLIF(es.owner_l1_name, '-1') AS l1_cc,
        NULLIF(es.owner_l2_name, '-1') AS l2_cc,
        NULLIF(es.owner_l3_name, '-1') AS l3_cc,
        NULLIF(LOWER(es.team), '-1') AS team,
        CONCAT(
            LOWER(es.cost_center_code),
            ' - ',
            SUBSTRING(LOWER(es.cost_center_name), 10)
        ) AS cost_center_label,
        CASE
            WHEN es.is_manager IS TRUE
                OR LOWER(es.job_name) LIKE '%talent%'
                OR LOWER(es.job_name) LIKE '%hrbp%'
                THEN 'LIDER'
            ELSE 'IC'
        END AS training_profile
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND es.is_primary_assignment_for_snapshot = TRUE
        AND LOWER(es.status) = 'active'
        AND (
            TRY_CAST(es.band AS INT) >= 7
            OR es.is_manager IS TRUE
            OR LOWER(es.job_name) LIKE '%talent%'
        )
        AND (
            es.months_employee_tenure >= 5
            OR es.is_manager IS TRUE
            OR LOWER(es.job_name) LIKE '%talent%'
        )
),
ranked_pathways AS (
    SELECT
        im.work_email,
        ac.id_user,
        ac.id_pathway,
        ac.pct_completed_required,
        MIN(ac.dt_completion) OVER (
            PARTITION BY im.work_email, ac.id_pathway
        ) AS first_completed_date,
        MAX(ac.dt_completion) OVER (
            PARTITION BY im.work_email, ac.id_pathway
        ) AS last_completed_date,
        ROW_NUMBER() OVER (
            PARTITION BY im.work_email
            ORDER BY
                CASE
                    WHEN ac.pct_completed_required = 100 THEN 1
                    ELSE 2
                END ASC,
                ac.dt_completion ASC,
                ac.pct_completed_required DESC
        ) AS priority_rank
    FROM
        datalake_learning.all_completions AS ac
    INNER JOIN
        datalake_learning.user_identifier_mapping AS im
            ON im.id_user = ac.id_user
    INNER JOIN
        eligible_employees AS ee
            ON ee.email = im.work_email
    WHERE
        im.work_email IS NOT NULL
        AND ac.id_pathway IN ('QQRXj', 'k4PR7', 'L6Wb7', 'y08qk', 'pRNgy', 'RjgQ5')
        AND ac.learning_object_type = 'Pathway'
        AND (
            ac.pct_completed_required > 0
            OR ac.dt_completion IS NOT NULL
        )
        AND NOT (
            ee.training_profile = 'LIDER'
            AND ac.id_pathway IN ('y08qk', 'pRNgy', 'RjgQ5')
        )
),
employees_with_pathway_defaults AS (
    SELECT
        ee.person_number,
        ee.employee_name,
        ee.email,
        ee.band,
        ee.job_name,
        ee.dt_hired,
        ee.is_leader_flag,
        ee.vertical,
        ee.manager_email,
        ee.hrbp,
        ee.manager_name,
        ee.country,
        ee.dedicated_product_brand,
        ee.company_tenure_months,
        ee.structure,
        ee.l1_cc,
        ee.l2_cc,
        ee.l3_cc,
        ee.team,
        ee.cost_center_label,
        ee.training_profile,
        COALESCE(
            rp.id_pathway,
            CASE
                WHEN LOWER(ee.country) IN ('brasil', 'br', 'brazil')
                    AND ee.training_profile = 'LIDER' THEN 'QQRXj'
                WHEN LOWER(ee.country) IN ('brasil', 'br', 'brazil')
                    AND ee.training_profile = 'IC' THEN 'y08qk'
                WHEN LOWER(ee.country) IN (
                        'mexico',
                        'méxico',
                        'argentina',
                        'colombia',
                        'colômbia',
                        'peru',
                        'chile',
                        'latam',
                        'panama',
                        'ecuador'
                    )
                    AND ee.training_profile = 'LIDER' THEN 'L6Wb7'
                WHEN LOWER(ee.country) IN (
                        'mexico',
                        'méxico',
                        'argentina',
                        'colombia',
                        'colômbia',
                        'peru',
                        'chile',
                        'latam',
                        'panama',
                        'ecuador'
                    )
                    AND ee.training_profile = 'IC' THEN 'RjgQ5'
                WHEN LOWER(ee.country) IN ('portugal', 'pt')
                    AND ee.training_profile = 'LIDER' THEN 'k4PR7'
                WHEN LOWER(ee.country) IN ('portugal', 'pt')
                    AND ee.training_profile = 'IC' THEN 'pRNgy'
                ELSE 'Revisar'
            END
        ) AS id_pathway_final,
        COALESCE(rp.pct_completed_required, 0) AS pct_completed_required_final,
        rp.first_completed_date,
        rp.last_completed_date
    FROM
        eligible_employees AS ee
    LEFT JOIN
        ranked_pathways AS rp
            ON ee.email = rp.work_email
            AND rp.priority_rank = 1
)
SELECT
    CASE
        WHEN ewp.id_pathway_final = 'QQRXj' THEN 'License to hire | Líder de pessoas'
        WHEN ewp.id_pathway_final = 'y08qk' THEN 'License to hire | Pessoas entrevistadoras'
        WHEN ewp.id_pathway_final = 'L6Wb7' THEN 'License to hire | Liderazgo'
        WHEN ewp.id_pathway_final = 'RjgQ5' THEN 'License to hire | Entrevistadores'
        WHEN ewp.id_pathway_final = 'k4PR7' THEN 'License to Hire | Leaders'
        WHEN ewp.id_pathway_final = 'pRNgy' THEN 'License to Hire | Interviewers'
        ELSE 'Revisar - Sem Trilha Mapeada'
    END AS titulo_trilha,
    ewp.id_pathway_final,
    'Internal' AS tipo_trilha,
    ewp.person_number AS matricula,
    ewp.employee_name AS nome,
    ewp.email,
    CONCAT(
        FORMAT_STRING('%.2f', CAST(ewp.pct_completed_required_final AS DOUBLE)),
        '%'
    ) AS pct_completed_required_final,
    CAST(NULL AS DATE) AS comecou_seguir,
    DATE_FORMAT(ewp.first_completed_date, 'MM/dd/yyyy') AS first_completed_date,
    DATE_FORMAT(ewp.last_completed_date, 'MM/dd/yyyy') AS last_completed_date,
    ewp.band AS banda,
    ewp.job_name AS cargo,
    ewp.dt_hired AS dt_inicio,
    CASE
        WHEN ewp.training_profile = 'LIDER' THEN 'L'
        ELSE 'CI'
    END AS perfil_treinamento,
    ewp.vertical,
    ewp.manager_email AS email_gestor,
    ewp.hrbp,
    ewp.manager_name AS gestor,
    UPPER(ewp.country) AS pais,
    ewp.dedicated_product_brand AS marca_produto_dedicado,
    ewp.company_tenure_months AS idade_empresa,
    ewp.structure,
    ewp.l1_cc,
    ewp.l2_cc,
    ewp.l3_cc,
    ewp.team,
    ewp.cost_center_label AS centro_de_custo,
    DATE(lt.ts_load_max) AS ts_load,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    employees_with_pathway_defaults AS ewp
CROSS JOIN
    load_timestamp AS lt
