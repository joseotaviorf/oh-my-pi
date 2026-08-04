-- QuintoCred employee applications in Greenhouse for TA visibility.
WITH quintocred_roster AS (
    SELECT DISTINCT
        CAST(REGEXP_REPLACE(CAST(roster.matricula AS STRING), '[^0-9]', '') AS STRING) AS person_number,
        LOWER(roster.nome) AS roster_name
    FROM
        datalake_gsheets_people_clean.quintocred_ta_roster AS roster
    WHERE
        roster.matricula IS NOT NULL
),
base_qc AS (
    SELECT
        LOWER(es.work_email) AS email,
        CAST(es.person_number AS BIGINT) AS matricula,
        roster.roster_name AS nome,
        LOWER(es.personal_email) AS email_pessoal,
        CASE
            WHEN LOWER(es.status) = 'active' THEN 'ativo'
            WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
            ELSE LOWER(es.status)
        END AS status_5a
    FROM
        metric_people.employee_snapshots AS es
    INNER JOIN
        quintocred_roster AS roster
            ON es.person_number = roster.person_number
    WHERE
        es.is_current = TRUE
        AND es.is_primary_assignment_for_snapshot = TRUE
),
candidate_emails AS (
    SELECT
        c.id_candidate AS id_candidate,
        c.full_name,
        em.value AS email
    FROM
        datalake_greenhouse_v3_clean.candidates AS c
        LATERAL VIEW EXPLODE(email_addresses) AS em
),
current_stage_ranked AS (
    SELECT
        astg.id_application,
        curr_stage.name AS current_stage_name,
        ROW_NUMBER() OVER (
            PARTITION BY astg.id_application
            ORDER BY astg.ts_updated DESC NULLS LAST, astg.id DESC
        ) AS rn
    FROM
        datalake_greenhouse_v3_clean.application_stages AS astg
    INNER JOIN
        datalake_greenhouse_v3_clean.job_interview_stages AS curr_stage
            ON curr_stage.id_job_interview_stage = astg.id_job_interview_stage
    WHERE
        astg.is_current = TRUE
),
current_stage AS (
    SELECT
        id_application,
        current_stage_name
    FROM
        current_stage_ranked
    WHERE
        rn = 1
)
SELECT DISTINCT
    a.id_application AS id_candidate,
    j.id_requisition AS id_job,
    qc.matricula AS matricula_5a,
    cand.full_name AS nome,
    qc.email_pessoal,
    qc.email AS email_corporativo,
    qc.status_5a,
    j.name AS job_name,
    a.status AS status_candidato_na_job,
    rr.name AS motivo_desqualificacao,
    CAST(a.ts_created AS DATE) AS dt_aplicacao,
    cs.current_stage_name AS etapa_atual,
    d.name AS departamento_1,
    dp.name AS departamento_2,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    datalake_greenhouse_v3_clean.applications AS a
LEFT JOIN
    candidate_emails AS ce
        ON ce.id_candidate = a.id_candidate
INNER JOIN
    base_qc AS qc
        ON (
            qc.email = ce.email
            OR qc.email_pessoal = ce.email
            OR LOWER(qc.nome) = LOWER(ce.full_name)
        )
LEFT JOIN
    datalake_greenhouse_v3_clean.jobs AS j
        ON j.id_job = a.id_job
LEFT JOIN
    datalake_greenhouse_v3_clean.candidates AS cand
        ON cand.id_candidate = a.id_candidate
LEFT JOIN
    datalake_greenhouse_v3_clean.rejection_details AS rd
        ON rd.id_application = a.id_application
LEFT JOIN
    datalake_greenhouse_v3_clean.rejection_reasons AS rr
        ON rr.id_rejection_reason = rd.id_rejection_reason
LEFT JOIN
    current_stage AS cs
        ON cs.id_application = a.id_application
LEFT JOIN
    datalake_greenhouse_v3_clean.departments AS d
        ON j.id_department = d.id_department
LEFT JOIN
    datalake_greenhouse_v3_clean.departments AS dp
        ON dp.id_department = d.id_parent
WHERE
    NOT a.is_prospect
