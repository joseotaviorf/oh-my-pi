-- Monthly job-tenure export for Paulo Golgher L1 scope (Engineering ICS tab).
WITH monthly_snapshots AS (
    SELECT
        es.dt_month_reference AS dt_month_end,
        LOWER(es.assignment_number) AS assignment_number,
        LOWER(es.name) AS employee_name,
        LOWER(es.work_email) AS email,
        LOWER(es.job_name) AS job_name,
        LOWER(CAST(es.band AS STRING)) AS band,
        LOWER(es.country) AS country,
        LOWER(es.email_l1) AS l1_e,
        LOWER(es.email_l2) AS l2_e,
        LOWER(es.email_l3) AS l3_e,
        LOWER(es.email_l4) AS l4_e,
        LOWER(es.email_l5) AS l5_e,
        LOWER(es.email_l6) AS l6_e,
        LOWER(es.email_l7) AS l7_e,
        es.dt_employee_hired AS dt_hired,
        es.months_employee_tenure AS tenure,
        LOWER(es.status) AS status
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_primary_assignment_for_snapshot = TRUE
        AND YEAR(es.dt_month_reference) >= 2025
),
job_start_dates AS (
    SELECT
        assignment_number,
        job_name,
        dt_month_end AS role_start_date,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_number, job_name
            ORDER BY dt_month_end ASC
        ) AS rn
    FROM
        monthly_snapshots
),
job_true_start AS (
    SELECT
        assignment_number,
        job_name,
        role_start_date
    FROM
        job_start_dates
    WHERE
        rn = 1
),
active_monthly_snapshots AS (
    SELECT
        assignment_number,
        employee_name,
        email,
        job_name,
        band,
        l1_e,
        l2_e,
        l3_e,
        l4_e,
        l5_e,
        l6_e,
        l7_e,
        dt_hired,
        tenure,
        dt_month_end,
        country
    FROM
        monthly_snapshots
    WHERE
        status = 'active'
)
SELECT DISTINCT
    f.dt_month_end AS fechamento,
    f.assignment_number AS id_colaborador,
    f.employee_name AS nome,
    f.email,
    f.job_name AS cargo,
    f.band AS banda,
    f.country AS pais,
    s.role_start_date AS inicio_cargo,
    TIMESTAMPDIFF(
        MONTH,
        DATE_TRUNC('MONTH', s.role_start_date),
        DATE_TRUNC('MONTH', f.dt_month_end)
    ) AS tempo_no_cargo_em_meses,
    f.dt_hired AS dt_inicio_empresa,
    f.tenure,
    f.l1_e,
    f.l2_e,
    f.l3_e,
    f.l4_e,
    f.l5_e,
    f.l6_e,
    f.l7_e,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    active_monthly_snapshots AS f
INNER JOIN
    job_true_start AS s
        ON f.assignment_number = s.assignment_number
        AND f.job_name = s.job_name
WHERE
    f.l1_e = 'paulo.golgher@quintoandar.com.br'
ORDER BY
    nome ASC,
    fechamento ASC
