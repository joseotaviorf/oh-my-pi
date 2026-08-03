-- Employees who gained extended days to complete Blitz regulatory training pathways.
-- Exception: Degreed learning enrich/clean tables — no DW equivalent for completion grain (DBP-1454).
-- Campaign window: 2026-04-16 through 2026-07-24; extended deadlines account for absences and new hires.

WITH
    degreed_content AS (
        SELECT
            ac.id_user,
            ac.id_section,
            ac.id_pathway,
            ac.id_learning_object,
            ac.learning_object_type,
            ac.content_required,
            ac.completed_required,
            CAST(100.0 * ac.completed_required / NULLIF(ac.content_required, 0) AS DECIMAL(10, 2)) AS pct_completed_content,
            ac.dt_completion,
            u.person_number,
            u.work_email AS user_organization_email,
            pd.title AS pathway_title,
            CASE
                WHEN sec.section_title IN ('Privacidad', 'Privacy', 'Privacidade') THEN 'Privacidade'
                WHEN sec.section_title IN ('Fraud', 'Fraude') THEN 'Fraude'
                WHEN sec.section_title = 'Cybersecurity' THEN 'Cybersecurity'
                WHEN sec.section_title = 'Compliance' THEN 'Compliance'
                ELSE sec.section_title
            END AS section_title_normalized,
            ac.ts_load
        FROM
            datalake_learning.all_completions AS ac
        LEFT JOIN
            datalake_learning.user_identifier_mapping AS u
                ON ac.id_user = u.id_user
        LEFT JOIN
            datalake_degreed_clean.pathway_details AS pd
                ON pd.id = ac.id_pathway
        LEFT JOIN
            datalake_learning.sections AS sec
                ON sec.id_section = ac.id_section
                AND sec.id_pathway = ac.id_pathway
        LEFT JOIN (
            SELECT DISTINCT
                id_content,
                is_required
            FROM
                datalake_learning.lesson_contents
        ) AS lec
            ON ac.id_learning_object = lec.id_content
        WHERE
            ac.learning_object_type = 'Content'
            AND lec.is_required = TRUE
    ),
    standardized_pathways AS (
        SELECT
            *,
            CASE
                WHEN id_pathway IN (
                    'Xry9A', 'jAvqw', '9Pd4e', '19j4Q', 'gd2QE', 'YWp8A', 'RjRPk', '9PKel'
                ) THEN 'Treinamento Regulatorio'
                ELSE 'Outros'
            END AS standardized_training
        FROM
            degreed_content
    ),
    section_progress AS (
        SELECT
            id_user,
            id_pathway,
            pathway_title,
            standardized_training,
            section_title_normalized,
            MAX(id_section) AS id_section,
            AVG(COALESCE(pct_completed_content, 0)) AS pct_completed_section
        FROM
            standardized_pathways
        GROUP BY
            id_user,
            id_pathway,
            pathway_title,
            standardized_training,
            section_title_normalized
    ),
    pathway_progress_calc AS (
        SELECT
            id_user,
            id_pathway,
            standardized_training,
            CAST(AVG(pct_completed_section) AS DECIMAL(10, 2)) AS pct_completed_pathway
        FROM
            section_progress
        GROUP BY
            id_user,
            id_pathway,
            standardized_training
    ),
    pathway_completion_dates AS (
        SELECT
            id_user,
            id_pathway,
            MAX(dt_completion) AS dt_pathway_completion,
            MAX(ts_load) AS max_ts_load
        FROM
            standardized_pathways
        GROUP BY
            id_user,
            id_pathway
    ),
    pathway_summary AS (
        SELECT DISTINCT
            tp.id_user,
            tp.user_organization_email,
            tp.person_number,
            tp.standardized_training,
            tp.pathway_title AS winning_pathway_title,
            tp.id_pathway,
            ptc.pct_completed_pathway,
            CASE
                WHEN ptc.pct_completed_pathway >= 100.0 THEN dc.dt_pathway_completion
                ELSE NULL
            END AS first_completion_date,
            dc.max_ts_load AS ts_load
        FROM
            standardized_pathways AS tp
        INNER JOIN
            pathway_progress_calc AS ptc
                ON tp.id_user = ptc.id_user
                AND tp.id_pathway = ptc.id_pathway
        INNER JOIN
            pathway_completion_dates AS dc
                ON tp.id_user = dc.id_user
                AND tp.id_pathway = dc.id_pathway
        WHERE
            tp.standardized_training = 'Treinamento Regulatorio'
    ),
    pathway_progress AS (
        SELECT
            id_user,
            user_organization_email,
            person_number,
            standardized_training,
            winning_pathway_title,
            id_pathway,
            pct_completed_pathway,
            first_completion_date,
            ts_load,
            ROW_NUMBER() OVER (
                PARTITION BY id_user, standardized_training
                ORDER BY
                    pct_completed_pathway DESC,
                    first_completion_date DESC NULLS LAST,
                    ts_load DESC
            ) AS rn
        FROM
            pathway_summary
    ),
    primary_pathway AS (
        SELECT
            id_user,
            user_organization_email,
            person_number,
            standardized_training,
            winning_pathway_title,
            id_pathway,
            pct_completed_pathway,
            first_completion_date
        FROM
            pathway_progress
        WHERE
            rn = 1
    ),
    absence_enrichment AS (
        SELECT
            far.person_number,
            SUM(
                CASE
                    WHEN CAST(far.dt_absence_started AS DATE) <= DATE '2026-07-24'
                        AND CAST(
                            COALESCE(
                                NULLIF(CAST(far.dt_absence_ended AS DATE), DATE '9999-12-31'),
                                DATE '2026-07-24'
                            ) AS DATE
                        ) >= DATE '2026-04-16'
                        AND far.sk_absence_type NOT IN (
                            300000004959159,
                            300000004800984,
                            300000135717548,
                            300000135717583,
                            300000004800949,
                            300000004959264
                        )
                        THEN DATEDIFF(
                            LEAST(
                                CAST(
                                    COALESCE(
                                        NULLIF(CAST(far.dt_absence_ended AS DATE), DATE '9999-12-31'),
                                        DATE '2026-07-24'
                                    ) AS DATE
                                ),
                                DATE '2026-07-24'
                            ),
                            GREATEST(CAST(far.dt_absence_started AS DATE), DATE '2026-04-16')
                        ) + 1
                    ELSE 0
                END
            ) AS dias_afastado_janela,
            CASE
                WHEN MAX(
                    CASE
                        WHEN CAST(far.dt_absence_started AS DATE) <= DATE '2026-07-24'
                            AND (
                                far.dt_absence_ended IS NULL
                                OR CAST(far.dt_absence_ended AS DATE) = DATE '9999-12-31'
                            )
                            AND far.sk_absence_type NOT IN (
                                300000004959159,
                                300000004800984,
                                300000135717548,
                                300000135717583,
                                300000004800949,
                                300000004959264
                            )
                            THEN 1
                        ELSE 0
                    END
                ) = 1
                    THEN NULL
                ELSE DATE_ADD(
                    MAX(
                        CASE
                            WHEN CAST(far.dt_absence_started AS DATE) <= DATE '2026-07-24'
                                AND CAST(far.dt_absence_ended AS DATE) >= DATE '2026-04-16'
                                AND CAST(far.dt_absence_ended AS DATE) < DATE '9999-12-31'
                                AND far.sk_absence_type NOT IN (
                                    300000004959159,
                                    300000004800984,
                                    300000135717548,
                                    300000135717583,
                                    300000004800949,
                                    300000004959264
                                )
                                THEN CAST(far.dt_absence_ended AS DATE)
                        END
                    ),
                    1
                )
            END AS dt_retorno
        FROM
            dw_time.fact_absence_requests AS far
        WHERE
            far.is_approved = TRUE
        GROUP BY
            far.person_number
    ),
    employee_current AS (
        SELECT
            es.person_number,
            es.name,
            es.dt_employee_hired AS dt_hired,
            es.name_l1,
            es.manager_name,
            es.manager_work_email,
            es.vertical,
            es.structure,
            es.band,
            es.status,
            ROW_NUMBER() OVER (
                PARTITION BY
                    es.person_number
                ORDER BY
                    CASE
                        WHEN LOWER(es.status) = 'active' THEN 0
                        ELSE 1
                    END,
                    es.assignment_number DESC
            ) AS es_rn
        FROM
            metric_people.employee_snapshots AS es
        WHERE
            es.is_current = TRUE
            AND es.is_primary_assignment_for_snapshot = TRUE
    ),
    base_final AS (
        SELECT
            f.user_organization_email AS email,
            f.winning_pathway_title AS trilha,
            f.pct_completed_pathway AS pct_conclusao_trilha,
            bc.name AS nome,
            bc.dt_hired AS dt_inicio,
            bc.name_l1 AS l1_gestor,
            bc.manager_name AS gestor,
            LOWER(bc.manager_work_email) AS email_gestor,
            NULLIF(LOWER(bc.vertical), '-1') AS vertical,
            NULLIF(LOWER(bc.structure), '-1') AS structure,
            bc.band AS banda,
            COALESCE(a.dias_afastado_janela, 0) AS dias_afastado_janela,
            a.dt_retorno,
            CASE
                WHEN CAST(bc.dt_hired AS DATE) BETWEEN DATE '2026-04-16' AND DATE '2026-07-24'
                    THEN LEAST(
                        GREATEST(
                            0,
                            DATEDIFF(
                                DATE_ADD(CAST(bc.dt_hired AS DATE), 90),
                                DATE '2026-07-24'
                            )
                        ) + COALESCE(a.dias_afastado_janela, 0),
                        90
                    )
                ELSE LEAST(COALESCE(a.dias_afastado_janela, 0), 90)
            END AS dias_ganhos
        FROM
            primary_pathway AS f
        LEFT JOIN
            employee_current AS bc
                ON f.person_number = bc.person_number
                AND bc.es_rn = 1
        LEFT JOIN
            absence_enrichment AS a
                ON f.person_number = a.person_number
        WHERE
            LOWER(bc.status) = 'active'
    ),
    deadline_calc AS (
        SELECT
            nome,
            email,
            dt_inicio,
            vertical,
            structure,
            banda,
            gestor,
            email_gestor,
            l1_gestor,
            trilha,
            pct_conclusao_trilha,
            dias_ganhos,
            CASE
                WHEN dt_retorno > DATE '2026-07-24'
                    THEN DATE_ADD(dt_retorno, CAST(dias_ganhos AS INT))
                ELSE DATE_ADD(DATE '2026-07-24', CAST(dias_ganhos AS INT))
            END AS data_limite_bruta
        FROM
            base_final
        WHERE
            dias_ganhos > 0
    )
SELECT
    nome,
    email,
    dt_inicio,
    vertical,
    structure,
    banda,
    gestor,
    email_gestor,
    l1_gestor,
    trilha,
    pct_conclusao_trilha,
    dias_ganhos,
    CASE DAYOFWEEK(data_limite_bruta)
        WHEN 7 THEN DATE_ADD(data_limite_bruta, 2)
        WHEN 1 THEN DATE_ADD(data_limite_bruta, 1)
        ELSE data_limite_bruta
    END AS data_final_ajustada,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    deadline_calc
ORDER BY
    nome,
    trilha ASC
