-- Monthly DEI analytics base for Looker (diversity flags, rewards cycle, committee).
WITH base_rewards AS (
    SELECT
        LOWER(fc.assignment_number) AS assignment_number,
        CONCAT(
            YEAR(fc.dt_valid_from),
            '/H',
            CASE
                WHEN MONTH(fc.dt_valid_from) <= 6 THEN 1
                ELSE 2
            END
        ) AS ciclo,
        MAX(
            CASE
                WHEN fc.is_promotion_movement = TRUE THEN 1
                WHEN LOWER(COALESCE(ed.reason_name, '')) LIKE '%promotion%' THEN 1
                WHEN LOWER(COALESCE(ed.reason_name_ptb, '')) LIKE '%promo%' THEN 1
                ELSE 0
            END
        ) AS fl_promocao,
        MAX(
            CASE
                WHEN LOWER(COALESCE(ed.reason_name, '')) LIKE '%merit%' THEN 1
                WHEN LOWER(COALESCE(ed.reason_name_ptb, '')) LIKE '%m_rito%' THEN 1
                WHEN LOWER(COALESCE(ed.reason_name_ptb, '')) = 'merito' THEN 1
                ELSE 0
            END
        ) AS fl_merito
    FROM
        dw_compensation.fact_compensations AS fc
    LEFT JOIN
        dw_compensation.dim_event_definition AS ed
            ON ed.sk_event_definition = fc.sk_event_definition
    WHERE
        fc.dt_valid_from >= DATE('2024-01-01')
        AND fc.assignment_number IS NOT NULL
    GROUP BY
        LOWER(fc.assignment_number),
        CONCAT(
            YEAR(fc.dt_valid_from),
            '/H',
            CASE
                WHEN MONTH(fc.dt_valid_from) <= 6 THEN 1
                ELSE 2
            END
        )
),
base_comites AS (
    SELECT
        f.person_number AS matricula,
        cm.committee_title AS comite
    FROM
        dw_performance.fact_performance_calibrations AS f
    LEFT JOIN
        dw_performance.dim_committee_meeting AS cm
            ON cm.sk_meeting = f.sk_committee_meeting
    WHERE
        cm.meeting_year = 2026
),
snapshot_base AS (
    SELECT
        es.sk_employee,
        LOWER(es.assignment_number) AS id_colaborador,
        es.dt_month_reference AS fechamento,
        es.person_number,
        es.months_tenure_in_company AS tenure,
        es.band AS banda,
        LOWER(es.status) AS status,
        LOWER(es.country) AS pais,
        NULLIF(LOWER(es.vertical), '-1') AS vertical,
        NULLIF(LOWER(es.structure), '-1') AS diretoria,
        LOWER(es.email_l1) AS l1_e,
        es.name_l2 AS l2_name,
        LOWER(es.hrbp_work_email) AS hrbp,
        LOWER(es.manager_work_email) AS email_gestor,
        CASE
            WHEN es.is_manager = TRUE THEN 'Leader'
            ELSE 'Non-Leader'
        END AS fl_lider,
        CASE
            WHEN es.is_leadership_team_member = TRUE THEN 'lt'
            ELSE NULL
        END AS fl_lt,
        COALESCE(es.count_direct_report, 0) AS diretos,
        LOWER(COALESCE(es.ethnicity, '')) AS ethnicity,
        LOWER(COALESCE(es.gender_identity, '')) AS gender_identity,
        LOWER(COALESCE(es.sexual_orientation, '')) AS sexual_orientation,
        LOWER(COALESCE(es.neurodiversity, '')) AS neurodiversity,
        es.has_medical_disability_record,
        LOWER(COALESCE(es.job_family, '')) AS job_family,
        LOWER(COALESCE(es.job_name, '')) AS job_name
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_primary_assignment_for_snapshot = TRUE
        AND es.dt_month_reference >= DATE('2024-03-31')
        AND LOWER(COALESCE(es.job_family, '')) NOT LIKE '%estag%'
        AND LOWER(COALESCE(es.job_family, '')) NOT LIKE '%jovem%'
        AND LOWER(COALESCE(es.job_name, '')) NOT LIKE '%estag%'
        AND LOWER(COALESCE(es.job_name, '')) NOT LIKE '%jovem%'
),
l1_index AS (
    SELECT
        fechamento,
        l1_e,
        COUNT(*) AS index_count
    FROM
        snapshot_base
    WHERE
        l1_e IS NOT NULL
    GROUP BY
        fechamento,
        l1_e
),
et_names AS (
    SELECT
        fechamento,
        LOWER(work_email) AS work_email,
        MAX(name) AS nome
    FROM (
        SELECT
            es.dt_month_reference AS fechamento,
            es.work_email,
            es.name
        FROM
            metric_people.employee_snapshots AS es
        WHERE
            es.is_primary_assignment_for_snapshot = TRUE
            AND es.work_email IS NOT NULL
            AND es.dt_month_reference >= DATE('2024-03-31')
    ) AS email_rows
    GROUP BY
        fechamento,
        LOWER(work_email)
),
disability_at_snapshot AS (
    SELECT
        sb.id_colaborador,
        sb.fechamento,
        dis.category,
        dis.is_active
    FROM
        snapshot_base AS sb
    LEFT JOIN
        dw_demographics.dim_employee_disability AS dis
            ON dis.sk_employee = sb.sk_employee
            AND dis.is_primary = TRUE
            AND sb.fechamento >= dis.dt_valid_from
            AND sb.fechamento <= dis.dt_valid_to
),
base_dei AS (
    SELECT
        b.id_colaborador,
        b.fechamento,
        b.tenure,
        b.banda,
        b.status,
        b.pais,
        b.vertical,
        b.diretoria,
        CASE
            WHEN b.l1_e = 'rafael.castro@quintoandar.com.br' THEN 'rafael dantas de castro'
            WHEN l.index_count >= 30 THEN et.nome
            ELSE NULL
        END AS ET,
        b.l1_e,
        b.l2_name AS L2,
        b.hrbp,
        b.email_gestor,
        CASE
            WHEN d.is_active = TRUE OR b.has_medical_disability_record = TRUE THEN 'sim'
            ELSE 'nao'
        END AS pcd_laudo,
        b.fl_lider,
        CASE
            WHEN LOWER(COALESCE(d.category, '')) IN (
                'motor deficiency',
                'physical disability'
            ) THEN 'Physical disability'
            WHEN LOWER(COALESCE(d.category, '')) IN (
                'visual impairment',
                'visual disability'
            ) THEN 'Visual Disability'
            WHEN LOWER(COALESCE(d.category, '')) IN (
                'hearing impairment',
                'hearing disability'
            ) THEN 'Hearing Impairment'
            WHEN LOWER(COALESCE(d.category, '')) IN (
                'mental disorder',
                'intellectual disability'
            ) THEN 'Intellectual disability'
            WHEN LOWER(COALESCE(d.category, '')) IN ('múltiplo', 'multiplo', 'multiple') THEN 'Multiple'
            WHEN LOWER(COALESCE(d.category, '')) IN ('other', 'otro') THEN 'Other'
            ELSE 'N/A'
        END AS disability_type,
        CASE
            WHEN b.gender_identity IN ('woman transgender', 'man transgender', 'non binary') THEN 'Trans'
            ELSE 'Not Trans'
        END AS fl_trans,
        CASE
            WHEN b.neurodiversity NOT IN ('', '-1', 'neurotypical')
                AND b.neurodiversity IS NOT NULL THEN 'Neurodiverse'
            WHEN LOWER(COALESCE(d.category, '')) IN (
                'mental disorder',
                'intellectual disability'
            ) THEN 'Neurodiverse'
            ELSE 'Neurotypical'
        END AS fl_neurodiversity,
        b.fl_lt,
        CASE
            WHEN b.ethnicity IN ('white', 'asian') THEN 'Non-BIM'
            WHEN b.ethnicity IN (
                'black or african american',
                'two or more races',
                'american indian',
                'desativado black or african american'
            ) THEN 'BIM'
            WHEN b.ethnicity IN ('', '-1') THEN 'N/A'
            ELSE 'N/A'
        END AS BIM,
        CASE
            WHEN b.gender_identity IN ('woman cisgender', 'woman transgender') THEN 'Women'
            WHEN b.gender_identity IN ('man cisgender', 'man transgender') THEN 'Non-Women'
            WHEN b.gender_identity = 'prefer not to say' THEN 'Rather not answer'
            WHEN b.gender_identity IN ('other', 'non binary') THEN 'Other'
            ELSE 'N/A'
        END AS WOMEN,
        CASE
            WHEN b.sexual_orientation IN (
                'homosexual',
                'bisexual',
                'pansexual',
                'asexual',
                'other'
            )
                OR b.gender_identity IN (
                    'woman transgender',
                    'man transgender',
                    'non binary',
                    'other'
                ) THEN 'LGBT+'
            WHEN b.sexual_orientation = 'heterosexual' THEN 'Non-LGBT+'
            WHEN b.sexual_orientation LIKE '%rather not answer%'
                OR b.gender_identity = 'prefer not to say' THEN 'Rather not answer'
            WHEN b.sexual_orientation IN ('', '-1') THEN 'N/A'
            ELSE 'N/A'
        END AS LGBT,
        CASE
            WHEN b.sexual_orientation IN (
                'homosexual',
                'bisexual',
                'pansexual',
                'asexual',
                'other'
            )
                OR b.gender_identity IN (
                    'woman transgender',
                    'man transgender',
                    'non binary',
                    'other'
                )
                OR b.gender_identity IN ('woman cisgender', 'woman transgender')
                OR b.ethnicity IN (
                    'black or african american',
                    'two or more races',
                    'american indian',
                    'desativado black or african american'
                ) THEN 'URG'
            WHEN b.sexual_orientation = 'heterosexual'
                AND b.gender_identity IN ('man cisgender', 'man transgender')
                AND b.ethnicity IN ('white', 'asian') THEN 'Non-URG'
            ELSE 'N/A'
        END AS URG,
        CASE
            WHEN d.is_active = TRUE OR b.has_medical_disability_record = TRUE THEN 'PwD'
            ELSE 'Non-PwD'
        END AS PwD,
        b.diretos,
        b.person_number,
        MIN(b.fechamento) OVER (PARTITION BY b.person_number) AS data_entrada
    FROM
        snapshot_base AS b
    LEFT JOIN
        l1_index AS l
            ON b.l1_e = l.l1_e
            AND b.fechamento = l.fechamento
    LEFT JOIN
        et_names AS et
            ON b.l1_e = et.work_email
            AND b.fechamento = et.fechamento
    LEFT JOIN
        disability_at_snapshot AS d
            ON b.id_colaborador = d.id_colaborador
            AND b.fechamento = d.fechamento
),
base_with_lag AS (
    SELECT
        bd.*,
        LAG(bd.diretos) OVER (
            PARTITION BY bd.person_number
            ORDER BY bd.fechamento
        ) AS prev_diretos
    FROM
        base_dei AS bd
),
base_dei_ciclo AS (
    SELECT
        b.id_colaborador,
        b.fechamento,
        b.tenure,
        b.banda,
        b.status,
        b.pais,
        b.vertical,
        b.diretoria,
        b.ET,
        b.l1_e,
        b.L2,
        b.hrbp,
        b.email_gestor,
        b.pcd_laudo,
        b.fl_lider,
        b.disability_type,
        b.fl_trans,
        b.fl_neurodiversity,
        CASE
            WHEN b.fl_lt IN ('lt', 'LT') THEN 'Yes'
            ELSE 'No'
        END AS LT,
        CAST(NULL AS STRING) AS modo,
        b.BIM,
        b.WOMEN,
        b.LGBT,
        b.URG,
        b.PwD,
        CASE
            WHEN COALESCE(b.prev_diretos, 0) = 0
                AND COALESCE(b.diretos, 0) > 0 THEN 1
            ELSE 0
        END AS fl_virou_lider,
        CASE
            WHEN b.fechamento = b.data_entrada THEN 1
            ELSE 0
        END AS fl_new_hire,
        CONCAT(
            YEAR(b.fechamento),
            '/H',
            CASE
                WHEN MONTH(b.fechamento) <= 6 THEN 1
                ELSE 2
            END
        ) AS ciclo,
        b.person_number
    FROM
        base_with_lag AS b
),
base_dei_rewards AS (
    SELECT
        d.*,
        COALESCE(r.fl_promocao, 0) AS fl_promocao,
        COALESCE(r.fl_merito, 0) AS fl_merito
    FROM
        base_dei_ciclo AS d
    LEFT JOIN
        base_rewards AS r
            ON d.id_colaborador = r.assignment_number
            AND d.ciclo = r.ciclo
),
base_dei_final AS (
    SELECT
        id_colaborador,
        fechamento,
        tenure,
        banda,
        status,
        pais,
        vertical,
        diretoria,
        ET,
        l1_e,
        L2,
        hrbp,
        email_gestor,
        pcd_laudo,
        fl_lider,
        disability_type,
        fl_trans,
        fl_neurodiversity,
        LT,
        modo,
        BIM,
        WOMEN,
        LGBT,
        URG,
        PwD,
        fl_virou_lider,
        fl_new_hire,
        ciclo,
        person_number,
        MAX(fl_promocao) AS fl_promocao,
        MAX(fl_merito) AS fl_merito,
        COUNT(*) AS qtd
    FROM
        base_dei_rewards
    GROUP BY
        id_colaborador,
        fechamento,
        tenure,
        banda,
        status,
        pais,
        vertical,
        diretoria,
        ET,
        l1_e,
        L2,
        hrbp,
        email_gestor,
        pcd_laudo,
        fl_lider,
        disability_type,
        fl_trans,
        fl_neurodiversity,
        LT,
        modo,
        BIM,
        WOMEN,
        LGBT,
        URG,
        PwD,
        fl_virou_lider,
        fl_new_hire,
        ciclo,
        person_number
)
SELECT
    bf.id_colaborador,
    bf.fechamento,
    bf.tenure,
    bf.banda,
    bf.status,
    bf.pais,
    bf.vertical,
    bf.diretoria,
    bf.ET,
    bf.l1_e,
    bf.L2,
    bf.hrbp,
    bf.email_gestor,
    bf.pcd_laudo,
    bf.fl_lider,
    bf.disability_type,
    bf.fl_trans,
    bf.fl_neurodiversity,
    bf.LT,
    bf.modo,
    bf.BIM,
    bf.WOMEN,
    bf.LGBT,
    bf.URG,
    bf.PwD,
    bf.fl_virou_lider,
    bf.fl_new_hire,
    bf.ciclo,
    bf.fl_promocao,
    bf.fl_merito,
    bf.qtd,
    com.comite,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    base_dei_final AS bf
LEFT JOIN
    base_comites AS com
        ON bf.person_number = com.matricula
ORDER BY
    bf.fechamento,
    bf.diretoria,
    bf.vertical,
    bf.pais,
    bf.status,
    bf.email_gestor,
    bf.pcd_laudo
