-- Current-month band tenure for Tech HRBPs (Paulo + Rafael L1 scopes).
WITH monthly_snapshots AS (
    SELECT
        es.dt_month_reference AS dt_month_end,
        es.person_number,
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
        es.months_employee_tenure AS company_tenure_months,
        LOWER(es.status) AS status,
        LOWER(es.business_unit_name) AS business_unit_name
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_primary_assignment_for_snapshot = TRUE
        AND YEAR(es.dt_month_reference) >= 2025
        AND (
            LOWER(es.business_unit_name) NOT LIKE '%classified%'
            OR (
                LOWER(es.business_unit_name) LIKE '%classified%'
                AND es.dt_month_reference > DATE '2024-10-01'
            )
        )
),
band_start_dates AS (
    SELECT
        person_number,
        band,
        MIN(dt_month_end) AS band_start_date
    FROM
        monthly_snapshots
    GROUP BY
        person_number,
        band
),
active_monthly_snapshots AS (
    SELECT
        person_number,
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
        company_tenure_months,
        dt_month_end,
        country
    FROM
        monthly_snapshots
    WHERE
        status = 'active'
        AND l1_e IN (
            'paulo.golgher@quintoandar.com.br',
            'rafael.castro@quintoandar.com.br'
        )
),
monthly_band_tenure AS (
    SELECT
        f.dt_month_end,
        f.person_number,
        f.employee_name,
        f.email,
        f.job_name,
        f.band,
        f.country,
        s.band_start_date,
        CASE
            WHEN (
                f.country IN ('argentina', 'mexico')
                AND s.band_start_date <= DATE '2024-10-01'
            ) THEN TIMESTAMPDIFF(
                MONTH,
                DATE_TRUNC('MONTH', DATE '2024-10-01'),
                DATE_TRUNC('MONTH', f.dt_month_end)
            )
            ELSE TIMESTAMPDIFF(
                MONTH,
                DATE_TRUNC('MONTH', s.band_start_date),
                DATE_TRUNC('MONTH', f.dt_month_end)
            )
        END AS months_in_band,
        f.dt_hired AS dt_company_start,
        f.company_tenure_months,
        f.l1_e,
        f.l2_e,
        f.l3_e,
        f.l4_e,
        f.l5_e,
        f.l6_e,
        f.l7_e
    FROM
        active_monthly_snapshots AS f
    INNER JOIN
        band_start_dates AS s
            ON f.person_number = s.person_number
            AND f.band = s.band
),
latest_month_end AS (
    SELECT
        MAX(dt_month_end) AS dt_month_end
    FROM
        monthly_band_tenure
)
SELECT DISTINCT
    bf.dt_month_end AS fechamento,
    bf.person_number,
    bf.employee_name AS nome,
    bf.email,
    bf.job_name AS cargo,
    bf.band AS banda,
    bf.country AS pais,
    bf.band_start_date AS inicio_banda,
    bf.months_in_band AS tempo_na_banda_em_meses,
    bf.dt_company_start AS dt_inicio_empresa,
    bf.company_tenure_months AS tempo_de_casa,
    bf.l1_e,
    bf.l2_e,
    bf.l3_e,
    bf.l4_e,
    bf.l5_e,
    bf.l6_e,
    bf.l7_e,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    monthly_band_tenure AS bf
INNER JOIN
    latest_month_end AS lf
        ON bf.dt_month_end = lf.dt_month_end
ORDER BY
    nome ASC,
    fechamento ASC
