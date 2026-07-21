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
committee_by_person AS (
    SELECT
        f.person_number AS person_number,
        cm.committee_title AS committee_title
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
        LOWER(es.assignment_number) AS assignment_number,
        es.dt_month_reference AS dt_month_end,
        es.person_number,
        es.months_employee_tenure AS tenure,
        es.band AS band,
        LOWER(es.status) AS status,
        LOWER(es.country) AS country,
        NULLIF(LOWER(es.vertical), '-1') AS vertical,
        NULLIF(LOWER(es.structure), '-1') AS directorate,
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
        COALESCE(es.count_direct_report, 0) AS direct_report_count,
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
        dt_month_end,
        l1_e,
        COUNT(*) AS index_count
    FROM
        snapshot_base
    WHERE
        l1_e IS NOT NULL
    GROUP BY
        dt_month_end,
        l1_e
),
executive_team_names AS (
    SELECT
        dt_month_end,
        LOWER(work_email) AS work_email,
        MAX(name) AS employee_name
    FROM (
        SELECT
            es.dt_month_reference AS dt_month_end,
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
        dt_month_end,
        LOWER(work_email)
),
disability_at_snapshot AS (
    SELECT
        sb.assignment_number,
        sb.dt_month_end,
        dis.category,
        dis.is_active
    FROM
        snapshot_base AS sb
    LEFT JOIN
        dw_demographics.dim_employee_disability AS dis
            ON dis.sk_employee = sb.sk_employee
            AND dis.is_primary = TRUE
            AND sb.dt_month_end >= dis.dt_valid_from
            AND sb.dt_month_end <= dis.dt_valid_to
),
dei_enriched AS (
    SELECT
        b.assignment_number,
        b.dt_month_end,
        b.tenure,
        b.band,
        b.status,
        b.country,
        b.vertical,
        b.directorate,
        CASE
            WHEN b.l1_e = 'rafael.castro@quintoandar.com.br' THEN 'rafael dantas de castro'
            WHEN l.index_count >= 30 THEN et.employee_name
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
        b.direct_report_count,
        b.person_number,
        MIN(b.dt_month_end) OVER (PARTITION BY b.person_number) AS hire_month_end
    FROM
        snapshot_base AS b
    LEFT JOIN
        l1_index AS l
            ON b.l1_e = l.l1_e
            AND b.dt_month_end = l.dt_month_end
    LEFT JOIN
        executive_team_names AS et
            ON b.l1_e = et.work_email
            AND b.dt_month_end = et.dt_month_end
    LEFT JOIN
        disability_at_snapshot AS d
            ON b.assignment_number = d.assignment_number
            AND b.dt_month_end = d.dt_month_end
),
dei_with_lag AS (
    SELECT
        de.*,
        LAG(de.direct_report_count) OVER (
            PARTITION BY de.person_number
            ORDER BY de.dt_month_end
        ) AS prev_direct_report_count
    FROM
        dei_enriched AS de
),
dei_with_cycle AS (
    SELECT
        b.assignment_number,
        b.dt_month_end,
        b.tenure,
        b.band,
        b.status,
        b.country,
        b.vertical,
        b.directorate,
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
            WHEN COALESCE(b.prev_direct_report_count, 0) = 0
                AND COALESCE(b.direct_report_count, 0) > 0 THEN 1
            ELSE 0
        END AS fl_virou_lider,
        CASE
            WHEN b.dt_month_end = b.hire_month_end THEN 1
            ELSE 0
        END AS fl_new_hire,
        CONCAT(
            YEAR(b.dt_month_end),
            '/H',
            CASE
                WHEN MONTH(b.dt_month_end) <= 6 THEN 1
                ELSE 2
            END
        ) AS ciclo,
        b.person_number
    FROM
        dei_with_lag AS b
),
dei_with_rewards AS (
    SELECT
        d.*,
        COALESCE(r.fl_promocao, 0) AS fl_promocao,
        COALESCE(r.fl_merito, 0) AS fl_merito
    FROM
        dei_with_cycle AS d
    LEFT JOIN
        base_rewards AS r
            ON d.assignment_number = r.assignment_number
            AND d.ciclo = r.ciclo
),
dei_aggregated AS (
    SELECT
        assignment_number,
        dt_month_end,
        tenure,
        band,
        status,
        country,
        vertical,
        directorate,
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
        dei_with_rewards
    GROUP BY
        assignment_number,
        dt_month_end,
        tenure,
        band,
        status,
        country,
        vertical,
        directorate,
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
    da.assignment_number AS id_colaborador,
    da.dt_month_end AS fechamento,
    da.tenure,
    da.band AS banda,
    da.status,
    da.country AS pais,
    da.vertical,
    da.directorate AS diretoria,
    da.ET,
    da.l1_e,
    da.L2,
    da.hrbp,
    da.email_gestor,
    da.pcd_laudo,
    da.fl_lider,
    da.disability_type,
    da.fl_trans,
    da.fl_neurodiversity,
    da.LT,
    da.modo,
    da.BIM,
    da.WOMEN,
    da.LGBT,
    da.URG,
    da.PwD,
    da.fl_virou_lider,
    da.fl_new_hire,
    da.ciclo,
    da.fl_promocao,
    da.fl_merito,
    da.qtd,
    com.committee_title AS comite,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    dei_aggregated AS da
LEFT JOIN
    committee_by_person AS com
        ON da.person_number = com.person_number
ORDER BY
    da.dt_month_end,
    da.directorate,
    da.vertical,
    da.country,
    da.status,
    da.email_gestor,
    da.pcd_laudo
