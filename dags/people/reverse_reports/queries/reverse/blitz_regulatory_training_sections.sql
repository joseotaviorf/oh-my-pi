-- Regulatory training section progress for the Blitz Looker dashboard.
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
            MAX(
                CASE
                    WHEN CAST(far.dt_absence_started AS DATE) <= CURRENT_DATE
                        AND (
                            CAST(far.dt_absence_ended AS DATE) = DATE '9999-12-31'
                            OR CAST(far.dt_absence_ended AS DATE) >= CURRENT_DATE
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
            ) AS absence_ativo,
            MAX(
                CASE
                    WHEN far.dt_absence_started >= DATE '2026-04-16'
                        THEN 1
                    ELSE 0
                END
            ) AS entrou_licenca,
            MAX(
                CASE
                    WHEN CAST(far.dt_absence_ended AS DATE) >= DATE '2026-04-16'
                        AND CAST(far.dt_absence_ended AS DATE) < DATE '9999-12-31'
                        THEN 1
                    ELSE 0
                END
            ) AS voltou_licenca,
            MAX(
                CASE
                    WHEN CAST(far.dt_absence_started AS DATE) <= CURRENT_DATE
                        AND (
                            CAST(far.dt_absence_ended AS DATE) = DATE '9999-12-31'
                            OR CAST(far.dt_absence_ended AS DATE) >= CURRENT_DATE
                        )
                        AND far.sk_absence_type NOT IN (
                            300000004959159,
                            300000004800984,
                            300000135717548,
                            300000135717583,
                            300000004800949,
                            300000004959264
                        )
                        THEN dat.absence_type
                END
            ) AS absence_type_ativo,
            ARRAY_JOIN(
                ARRAY_AGG(DISTINCT dat.absence_type) FILTER (WHERE dat.absence_type IS NOT NULL),
                ', '
            ) AS absence_types,
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
        LEFT JOIN
            dw_time.dim_absence_type AS dat
                ON far.sk_absence_type = dat.sk_absence_type
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
            es.country,
            es.name_l1,
            es.name_l2,
            es.name_l3,
            es.manager_name,
            es.vertical,
            es.structure,
            es.is_manager,
            es.band,
            es.access_list_no_employee,
            es.status,
            bu.consolidated_business_unit_name,
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
        LEFT JOIN
            dw_organization.dim_business_unit AS bu
                ON bu.sk_business_unit = es.sk_business_unit
        WHERE
            es.is_current = TRUE
            AND es.is_primary_assignment_for_snapshot = TRUE
    ),
    base_final AS (
        SELECT
            f.id_user AS degreed_user_id,
            f.user_organization_email AS email,
            f.person_number,
            f.standardized_training AS treinamento_padronizado,
            f.winning_pathway_title AS pathway_title_escolhida,
            f.pct_completed_pathway,
            f.first_completion_date AS primeira_data_conclusao,
            c.section_title_normalized AS section_title,
            c.id_section,
            c.pct_completed_section AS pct_completed_content,
            bc.name AS nome,
            bc.dt_hired AS dt_inicio,
            LOWER(bc.country) AS pais,
            bc.consolidated_business_unit_name AS empresa,
            bc.name_l1 AS l1_gestor,
            bc.name_l2 AS l2_gestor,
            bc.name_l3 AS l3_gestor,
            bc.manager_name AS gestor,
            NULLIF(LOWER(bc.vertical), '-1') AS vertical,
            NULLIF(LOWER(bc.structure), '-1') AS structure,
            CASE
                WHEN bc.is_manager IS TRUE THEN 1
                ELSE 0
            END AS fl_lider,
            bc.band AS banda,
            bc.access_list_no_employee,
            COALESCE(a.absence_ativo, 0) AS absence_ativo,
            COALESCE(a.entrou_licenca, 0) AS entrou_licenca,
            COALESCE(a.voltou_licenca, 0) AS voltou_licenca,
            a.absence_type_ativo,
            a.absence_types,
            COALESCE(a.dias_afastado_janela, 0) AS dias_afastado_janela,
            a.dt_retorno,
            CASE
                WHEN CAST(bc.dt_hired AS DATE) BETWEEN DATE '2026-04-16' AND DATE '2026-07-24'
                    THEN 1
                ELSE 0
            END AS fl_new_hire,
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
            section_progress AS c
                ON f.id_user = c.id_user
                AND f.id_pathway = c.id_pathway
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
            degreed_user_id,
            email,
            person_number,
            treinamento_padronizado,
            pathway_title_escolhida,
            pct_completed_pathway,
            primeira_data_conclusao,
            section_title,
            id_section,
            pct_completed_content,
            nome,
            dt_inicio,
            pais,
            empresa,
            l1_gestor,
            l2_gestor,
            l3_gestor,
            gestor,
            vertical,
            structure,
            fl_lider,
            banda,
            access_list_no_employee,
            absence_ativo,
            entrou_licenca,
            voltou_licenca,
            absence_type_ativo,
            absence_types,
            dias_afastado_janela,
            dt_retorno,
            fl_new_hire,
            dias_ganhos,
            CASE
                WHEN dias_ganhos > 0 THEN 1
                ELSE 0
            END AS fl_ganhou_dias,
            CASE
                WHEN dias_ganhos > 0
                    AND COALESCE(pct_completed_pathway, 0) < 100.0
                    THEN 1
                ELSE 0
            END AS fl_pendente_prazo_estendido,
            CASE
                WHEN dt_retorno > DATE '2026-07-24'
                    THEN DATE_ADD(dt_retorno, CAST(dias_ganhos AS INT))
                ELSE DATE_ADD(DATE '2026-07-24', CAST(dias_ganhos AS INT))
            END AS data_limite_bruta
        FROM
            base_final
    )
SELECT
    degreed_user_id,
    email,
    person_number,
    treinamento_padronizado,
    pathway_title_escolhida,
    pct_completed_pathway,
    primeira_data_conclusao,
    section_title,
    id_section,
    pct_completed_content,
    nome,
    dt_inicio,
    pais,
    empresa,
    l1_gestor,
    l2_gestor,
    l3_gestor,
    gestor,
    vertical,
    structure,
    fl_lider,
    banda,
    access_list_no_employee,
    absence_ativo,
    entrou_licenca,
    voltou_licenca,
    absence_type_ativo,
    absence_types,
    dias_afastado_janela,
    dt_retorno,
    fl_new_hire,
    dias_ganhos,
    fl_ganhou_dias,
    fl_pendente_prazo_estendido,
    data_limite_bruta,
    CASE DAYOFWEEK(data_limite_bruta)
        WHEN 7 THEN DATE_ADD(data_limite_bruta, 2)
        WHEN 1 THEN DATE_ADD(data_limite_bruta, 1)
        ELSE data_limite_bruta
    END AS nova_data_limite,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    deadline_calc
ORDER BY
    nome,
    treinamento_padronizado ASC
