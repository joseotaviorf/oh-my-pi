WITH demographics AS (
    SELECT
        answers.id_application AS id_application,
        questions.id_demographic_question AS question_id,
        options.id_demographic_answer_option AS answer_option_id,
        CASE
            WHEN options.name LIKE '%especifique%' THEN answers.free_form_text
            ELSE options.name
        END AS answer_option
    FROM
        datalake_greenhouse_v3_clean.demographic_answers AS answers
    LEFT JOIN
        datalake_greenhouse_v3_clean.demographic_questions AS questions
            ON answers.id_demographic_question = questions.id_demographic_question
    LEFT JOIN
        datalake_greenhouse_v3_clean.demographic_answer_options AS options
            ON answers.id_demographic_answer_option = options.id_demographic_answer_option
),
demographics_agg AS (
    SELECT
        dem.id_application AS id_application,
        MAX(
            CASE
                WHEN dem.question_id = 4003820009
                    AND dem.answer_option_id NOT IN (4022936009, 4022931009)
                    THEN TRUE
                ELSE FALSE
            END
        ) AS race_diversity,
        MAX(
            CASE
                WHEN dem.question_id = 4003826009
                    AND dem.answer_option_id = 4023188009
                    THEN TRUE
                ELSE FALSE
            END
        ) AS accessibility_diversity,
        MAX(
            CASE
                WHEN dem.question_id = 4003821009
                    AND dem.answer_option_id NOT IN (4022943009, 4022939009, 4022937009)
                    THEN TRUE
                ELSE FALSE
            END
        ) AS gender_diversity,
        MAX(
            CASE
                WHEN dem.question_id = 4003822009
                    AND dem.answer_option_id NOT IN (4022950009, 4022948009)
                    THEN TRUE
                ELSE FALSE
            END
        ) AS sexual_orientation_diversity,
        MAX(
            CASE
                WHEN dem.question_id = 4003823009
                    AND dem.answer_option_id = 4022951009
                    THEN TRUE
                ELSE FALSE
            END
        ) AS is_pwd,
        MAX(
            CASE
                WHEN dem.question_id = 4003825009
                    AND dem.answer_option_id NOT IN (4022963009, 4022969009)
                    THEN TRUE
                ELSE FALSE
            END
        ) AS is_neurodiversity
    FROM
        demographics AS dem
    GROUP BY
        dem.id_application
),
applications_diversity AS (
    SELECT
        o.id_application_hired AS id_hired_application,
        CONCAT_WS(
            ' | ',
            CASE WHEN d.race_diversity THEN 'Raça/Etnia' END,
            CASE WHEN d.accessibility_diversity THEN 'Acessibilidade' END,
            CASE WHEN d.gender_diversity THEN 'Identidade de Gênero' END,
            CASE WHEN d.sexual_orientation_diversity THEN 'Orientação Sexual' END,
            CASE WHEN d.is_pwd THEN 'PcD' END,
            CASE WHEN d.is_neurodiversity THEN 'Neurodiversidade' END
        ) AS diverse_hire_dimensions
    FROM
        datalake_hiring.job_openings AS o
    LEFT JOIN
        demographics_agg AS d
            ON d.id_application = o.id_application_hired
    WHERE
        o.id_application_hired IS NOT NULL
),
unresolved_offers AS (
    SELECT DISTINCT
        ofr.id_opening AS id_opening
    FROM
        datalake_greenhouse_v3_clean.offers AS ofr
    WHERE
        LOWER(ofr.status) = 'created'
),
job_country AS (
    SELECT
        j.id_job AS id_job,
        LOWER(
            IF(
                offices_parent.name IS NULL,
                offices.name,
                offices_parent.name
            )
        ) AS country
    FROM
        datalake_greenhouse_v3_clean.jobs AS j
    LEFT JOIN
        datalake_greenhouse_v3_clean.offices AS offices
            ON j.office_ids[0] = offices.id_office
    LEFT JOIN
        datalake_greenhouse_v3_clean.offices AS offices_parent
            ON offices.id_parent = offices_parent.id_office
),
hiring_manager_l1 AS (
    SELECT
        TRIM(
            LOWER(
                REGEXP_REPLACE(es.work_email, '\\.com\\.br$', '.com')
            )
        ) AS email_key,
        LOWER(es.name_l1) AS l1_gestor
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND es.is_primary_assignment_for_snapshot = TRUE
)
SELECT
    o.id_opening AS req_id,
    o.code AS req_code,
    o.id_job AS job_id,
    CAST(j.ts_created AS DATE) AS job_created_on,
    CASE
        WHEN o.ts_closed IS NULL THEN NULL
        WHEN LOWER(COALESCE(cr.name, '')) LIKE 'canceled%'
            OR LOWER(COALESCE(cr.name, '')) = 'not approved'
            THEN CAST(o.ts_closed AS DATE)
    END AS canceled_on,
    CASE
        WHEN o.ts_closed IS NULL THEN NULL
        WHEN LOWER(COALESCE(cr.name, '')) LIKE 'hire%'
            OR LOWER(COALESCE(cr.name, '')) LIKE 'filled%'
            THEN CAST(o.ts_closed AS DATE)
    END AS filled_on,
    CASE
        WHEN unr.id_opening IS NOT NULL THEN 'reserved'
        WHEN cr.name = 'Hiring Freeze' THEN 'on hold - freezing'
        WHEN cr.name = 'On Hold - In queue' THEN 'on hold - in queue'
        WHEN LOWER(COALESCE(cr.name, '')) LIKE 'canceled%'
            OR LOWER(COALESCE(cr.name, '')) = 'not approved'
            THEN 'canceled'
        WHEN LOWER(COALESCE(cr.name, '')) LIKE 'hire%'
            OR LOWER(COALESCE(cr.name, '')) LIKE 'filled%'
            THEN 'filled'
        WHEN LOWER(COALESCE(cr.name, '')) LIKE 'on hold%' THEN 'on hold'
        WHEN LOWER(j.status) = 'draft' THEN 'draft'
        ELSE o.status
    END AS status,
    LOWER(j.name) AS job_name,
    o.affirmative_focus AS diversity_focus,
    NULLIF(apps_div.diverse_hire_dimensions, '') AS diverse_hire_dimensions,
    'GH' AS fl_system,
    hml.l1_gestor AS L1_hierarchy,
    o.cost_center AS cost_center,
    o.hiring_manager_email AS hiring_manager,
    o.ta_responsible_email AS requisition_owner,
    CASE
        WHEN o.request_reason LIKE '1. Replacement%'
            OR o.request_reason = 'Replacement'
            THEN 'Replacement'
        WHEN o.request_reason LIKE '2. New Position%'
            OR o.request_reason = 'New Position'
            THEN 'New Position'
        WHEN o.request_reason IS NULL THEN 'Without Information'
        ELSE o.request_reason
    END AS requisition_reason,
    CASE
        WHEN o.overhead_or_capacity IS NULL THEN 'Without information'
        ELSE o.overhead_or_capacity
    END AS hc_type_gh,
    jc.country AS country,
    LOWER(o.band) AS banda,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    datalake_hiring.job_openings AS o
INNER JOIN
    datalake_greenhouse_v3_clean.jobs AS j
        ON o.id_job = j.id_job
LEFT JOIN
    datalake_greenhouse_v3_clean.close_reasons AS cr
        ON o.id_close_reason = cr.id_close_reason
LEFT JOIN
    unresolved_offers AS unr
        ON unr.id_opening = o.id_opening
LEFT JOIN
    applications_diversity AS apps_div
        ON apps_div.id_hired_application = o.id_application_hired
LEFT JOIN
    job_country AS jc
        ON jc.id_job = j.id_job
LEFT JOIN
    hiring_manager_l1 AS hml
        ON hml.email_key = TRIM(
            LOWER(
                REGEXP_REPLACE(o.hiring_manager_email, '\\.com\\.br$', '.com')
            )
        )
WHERE
    CAST(j.ts_created AS DATE) >= DATE('2025-11-01')
    AND (
        jc.country = 'brasil'
        OR jc.country = 'não se aplica'
    )
    AND o.company IS NOT NULL
    AND LOWER(j.name) NOT LIKE '%felicidade%'
    AND LOWER(j.name) NOT LIKE '%container%'
    AND COALESCE(j.is_template, FALSE) = FALSE
    AND j.name <> 'Sample Job 1'
    AND LOWER(COALESCE(o.code, '')) NOT LIKE '%fake%'
    AND COALESCE(CAST(j.id_requisition AS STRING), '') NOT IN ('651', '643')
    AND COALESCE(o.code, '') <> '000-00'
