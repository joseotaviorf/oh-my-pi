-- License to Hire dashboard base: eligible employees and Degreed pathway completion.
-- Exception: learning progress comes from enrich `datalake_learning.*` — no `dw_learning` yet (DBP-1736).
WITH data_atualizacao AS (
    SELECT
        MAX(ac.ts_load) AS ts_load_max
    FROM
        datalake_learning.all_completions AS ac
    WHERE
        ac.id_pathway IN ('QQRXj', 'k4PR7', 'L6Wb7', 'y08qk', 'pRNgy', 'RjgQ5')
        AND ac.learning_object_type = 'Pathway'
),
base_funcionarios AS (
    SELECT
        es.person_number AS matricula,
        es.name AS nome,
        LOWER(es.work_email) AS email,
        es.band AS banda,
        es.job_name AS cargo,
        es.dt_hired AS dt_inicio,
        CASE
            WHEN es.is_manager IS TRUE THEN 1
            ELSE 0
        END AS fl_lider,
        NULLIF(LOWER(es.vertical), '-1') AS vertical,
        LOWER(es.manager_work_email) AS email_gestor,
        LOWER(es.hrbp_work_email) AS hrbp,
        es.manager_name AS gestor,
        LOWER(es.country) AS pais,
        NULLIF(LOWER(es.product), '-1') AS marca_produto_dedicado,
        es.months_tenure_in_company AS idade_empresa,
        NULLIF(LOWER(es.structure), '-1') AS structure,
        NULLIF(es.owner_l1_name, '-1') AS l1_cc,
        NULLIF(es.owner_l2_name, '-1') AS l2_cc,
        NULLIF(es.owner_l3_name, '-1') AS l3_cc,
        NULLIF(LOWER(es.team), '-1') AS team,
        CONCAT(
            LOWER(es.cost_center_code),
            ' - ',
            SUBSTRING(LOWER(es.cost_center_name), 10)
        ) AS centro_de_custo,
        CASE
            WHEN es.is_manager IS TRUE
                OR LOWER(es.job_name) LIKE '%talent%'
                OR LOWER(es.job_name) LIKE '%hrbp%'
                THEN 'LIDER'
            ELSE 'IC'
        END AS perfil_treinamento
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
            es.months_tenure_in_company >= 5
            OR es.is_manager IS TRUE
            OR LOWER(es.job_name) LIKE '%talent%'
        )
),
trilhas_ranqueadas AS (
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
        -- Rank by corporate email (sheet grain), not Degreed id_user: multiple Degreed
        -- accounts can share one work_email and would otherwise each get ranking = 1.
        ROW_NUMBER() OVER (
            PARTITION BY im.work_email
            ORDER BY
                CASE
                    WHEN ac.pct_completed_required = 100 THEN 1
                    ELSE 2
                END ASC,
                ac.dt_completion ASC,
                ac.pct_completed_required DESC
        ) AS ranking_prioridade
    FROM
        datalake_learning.all_completions AS ac
    INNER JOIN
        datalake_learning.user_identifier_mapping AS im
            ON im.id_user = ac.id_user
    INNER JOIN
        base_funcionarios AS f
            ON f.email = im.work_email
    WHERE
        im.work_email IS NOT NULL
        AND ac.id_pathway IN ('QQRXj', 'k4PR7', 'L6Wb7', 'y08qk', 'pRNgy', 'RjgQ5')
        AND ac.learning_object_type = 'Pathway'
        AND (
            ac.pct_completed_required > 0
            OR ac.dt_completion IS NOT NULL
        )
        AND NOT (
            f.perfil_treinamento = 'LIDER'
            AND ac.id_pathway IN ('y08qk', 'pRNgy', 'RjgQ5')
        )
),
base_com_valores_default AS (
    SELECT
        f.matricula,
        f.nome,
        f.email,
        f.banda,
        f.cargo,
        f.dt_inicio,
        f.fl_lider,
        f.vertical,
        f.email_gestor,
        f.hrbp,
        f.gestor,
        f.pais,
        f.marca_produto_dedicado,
        f.idade_empresa,
        f.structure,
        f.l1_cc,
        f.l2_cc,
        f.l3_cc,
        f.team,
        f.centro_de_custo,
        f.perfil_treinamento,
        COALESCE(
            t.id_pathway,
            CASE
                WHEN LOWER(f.pais) IN ('brasil', 'br', 'brazil')
                    AND f.perfil_treinamento = 'LIDER' THEN 'QQRXj'
                WHEN LOWER(f.pais) IN ('brasil', 'br', 'brazil')
                    AND f.perfil_treinamento = 'IC' THEN 'y08qk'
                WHEN LOWER(f.pais) IN (
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
                    AND f.perfil_treinamento = 'LIDER' THEN 'L6Wb7'
                WHEN LOWER(f.pais) IN (
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
                    AND f.perfil_treinamento = 'IC' THEN 'RjgQ5'
                WHEN LOWER(f.pais) IN ('portugal', 'pt')
                    AND f.perfil_treinamento = 'LIDER' THEN 'k4PR7'
                WHEN LOWER(f.pais) IN ('portugal', 'pt')
                    AND f.perfil_treinamento = 'IC' THEN 'pRNgy'
                ELSE 'Revisar'
            END
        ) AS id_pathway_final,
        COALESCE(t.pct_completed_required, 0) AS pct_completed_required_final,
        t.first_completed_date,
        t.last_completed_date
    FROM
        base_funcionarios AS f
    LEFT JOIN
        trilhas_ranqueadas AS t
            ON f.email = t.work_email
            AND t.ranking_prioridade = 1
)
SELECT
    CASE
        WHEN bcv.id_pathway_final = 'QQRXj' THEN 'License to hire | Líder de pessoas'
        WHEN bcv.id_pathway_final = 'y08qk' THEN 'License to hire | Pessoas entrevistadoras'
        WHEN bcv.id_pathway_final = 'L6Wb7' THEN 'License to hire | Liderazgo'
        WHEN bcv.id_pathway_final = 'RjgQ5' THEN 'License to hire | Entrevistadores'
        WHEN bcv.id_pathway_final = 'k4PR7' THEN 'License to Hire | Leaders'
        WHEN bcv.id_pathway_final = 'pRNgy' THEN 'License to Hire | Interviewers'
        ELSE 'Revisar - Sem Trilha Mapeada'
    END AS titulo_trilha,
    bcv.id_pathway_final,
    'Internal' AS tipo_trilha,
    bcv.matricula,
    bcv.nome,
    bcv.email,
    CONCAT(
        FORMAT_STRING('%.2f', CAST(bcv.pct_completed_required_final AS DOUBLE)),
        '%'
    ) AS pct_completed_required_final,
    CAST(NULL AS DATE) AS comecou_seguir,
    DATE_FORMAT(bcv.first_completed_date, 'MM/dd/yyyy') AS first_completed_date,
    DATE_FORMAT(bcv.last_completed_date, 'MM/dd/yyyy') AS last_completed_date,
    bcv.banda,
    bcv.cargo,
    bcv.dt_inicio,
    CASE
        WHEN bcv.perfil_treinamento = 'LIDER' THEN 'L'
        ELSE 'CI'
    END AS perfil_treinamento,
    bcv.vertical,
    bcv.email_gestor,
    bcv.hrbp,
    bcv.gestor,
    UPPER(bcv.pais) AS pais,
    bcv.marca_produto_dedicado,
    bcv.idade_empresa,
    bcv.structure,
    bcv.l1_cc,
    bcv.l2_cc,
    bcv.l3_cc,
    bcv.team,
    bcv.centro_de_custo,
    DATE(dt.ts_load_max) AS ts_load,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    base_com_valores_default AS bcv
CROSS JOIN
    data_atualizacao AS dt
