-- Regulatory training content progress for the Blitz Looker dashboard.
-- Exception: Degreed learning enrich/clean tables — no DW equivalent for completion grain (DBP-1454).

WITH
    degreed_content AS (
        SELECT
            ac.id_user,
            ac.id_section,
            ac.id_learning_object AS id_content,
            ac.id_pathway,
            ac.learning_object_type,
            ac.learning_object_order,
            ac.content_required,
            ac.content_optional,
            ac.content_total,
            ac.completed_required,
            ac.completed_optional,
            ac.completed_total,
            CAST(100.0 * ac.completed_required / NULLIF(ac.content_required, 0) AS DECIMAL(10, 2)) AS pct_completed_content,
            ac.dt_completion,
            u.person_number,
            u.work_email AS user_organization_email,
            pd.title AS pathway_title,
            cont.content_type,
            CASE
                WHEN sec.section_title IN ('Privacidad', 'Privacy', 'Privacidade') THEN 'Privacidade'
                WHEN sec.section_title IN ('Fraud', 'Fraude') THEN 'Fraude'
                WHEN sec.section_title = 'Cybersecurity' THEN 'Cybersecurity'
                WHEN sec.section_title = 'Compliance' THEN 'Compliance'
                ELSE sec.section_title
            END AS section_title_normalized,
            sec.section_sequence,
            cont.title AS content_title,
            les.lesson_title,
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
        LEFT JOIN
            datalake_degreed_clean.contents AS cont
                ON cont.id = ac.id_learning_object
        LEFT JOIN
            datalake_learning.lessons AS les
                ON les.id_lesson = ac.id_lesson
        LEFT JOIN (
            SELECT DISTINCT
                id_content,
                is_required
            FROM
                datalake_learning.lesson_contents
        ) AS lec
            ON cont.id = lec.id_content
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
            standardized_training,
            section_title_normalized,
            AVG(COALESCE(pct_completed_content, 0)) AS pct_completed_section
        FROM
            standardized_pathways
        GROUP BY
            id_user,
            id_pathway,
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
            tp.pathway_title,
            tp.id_pathway,
            ptc.pct_completed_pathway,
            CASE
                WHEN ptc.pct_completed_pathway >= 100.0 THEN dc.dt_pathway_completion
                ELSE NULL
            END AS completion_date_rank,
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
            *,
            ROW_NUMBER() OVER (
                PARTITION BY id_user, standardized_training
                ORDER BY
                    pct_completed_pathway DESC,
                    completion_date_rank DESC NULLS LAST,
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
            pathway_title,
            id_pathway,
            pct_completed_pathway
        FROM
            pathway_progress
        WHERE
            rn = 1
    ),
    content_progress AS (
        SELECT
            id_user,
            id_pathway,
            pathway_title,
            content_type,
            section_title_normalized AS section_title,
            id_section,
            id_content,
            lesson_title,
            content_title,
            pct_completed_content,
            CASE
                WHEN pct_completed_content >= 100.0 THEN dt_completion
                ELSE NULL
            END AS first_completion_date
        FROM
            standardized_pathways
    ),
    active_absences AS (
        SELECT
            person_number,
            MAX(
                CASE
                    WHEN CURRENT_DATE BETWEEN dt_absence_started AND dt_absence_ended THEN 1
                    ELSE 0
                END
            ) AS absence_ativo
        FROM
            dw_time.fact_absence_requests
        WHERE
            sk_absence_type NOT IN (
                300000004959159,
                300000004800984,
                300000135717548,
                300000135717583,
                300000004800949,
                300000004959264
            )
            AND is_approved = TRUE
        GROUP BY
            person_number
    ),
    employee_current AS (
        SELECT
            es.person_number,
            es.name,
            es.dt_hired,
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
    )
SELECT
    f.id_user AS degreed_user_id,
    f.user_organization_email AS email,
    f.person_number,
    f.standardized_training AS treinamento_padronizado,
    f.pathway_title AS pathway_title_escolhida,
    f.pct_completed_pathway,
    c.first_completion_date AS primeira_data_conclusao,
    c.section_title,
    c.id_section,
    c.id_content,
    c.lesson_title,
    c.content_title,
    c.content_type,
    c.pct_completed_content,
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
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    primary_pathway AS f
LEFT JOIN
    content_progress AS c
        ON f.id_user = c.id_user
        AND f.id_pathway = c.id_pathway
LEFT JOIN
    employee_current AS bc
        ON f.person_number = bc.person_number
        AND bc.es_rn = 1
LEFT JOIN
    active_absences AS a
        ON f.person_number = a.person_number
WHERE
    LOWER(bc.status) = 'active'
    AND (
        a.absence_ativo = 0
        OR a.absence_ativo IS NULL
    )
