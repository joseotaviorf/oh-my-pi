-- Monthly job-tenure export for Paulo Golgher L1 scope (Engineering ICS tab).
WITH monthly_snapshots AS (
    SELECT
        es.dt_month_reference AS fechamento,
        LOWER(es.assignment_number) AS id_colaborador,
        LOWER(es.name) AS nome,
        LOWER(es.work_email) AS email,
        LOWER(es.job_name) AS cargo,
        LOWER(CAST(es.band AS STRING)) AS banda,
        LOWER(es.country) AS pais,
        LOWER(es.email_l1) AS l1_e,
        LOWER(es.email_l2) AS l2_e,
        LOWER(es.email_l3) AS l3_e,
        LOWER(es.email_l4) AS l4_e,
        LOWER(es.email_l5) AS l5_e,
        LOWER(es.email_l6) AS l6_e,
        LOWER(es.email_l7) AS l7_e,
        es.dt_hired AS data_entrada,
        es.months_tenure_in_company AS tenure,
        LOWER(es.status) AS status
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_primary_assignment_for_snapshot = TRUE
        AND YEAR(es.dt_month_reference) >= 2025
),
cargo_start_dates AS (
    SELECT
        id_colaborador,
        cargo,
        fechamento AS inicio_cargo,
        ROW_NUMBER() OVER (
            PARTITION BY id_colaborador, cargo
            ORDER BY fechamento ASC
        ) AS rn
    FROM
        monthly_snapshots
),
cargo_true_start AS (
    SELECT
        id_colaborador,
        cargo,
        inicio_cargo
    FROM
        cargo_start_dates
    WHERE
        rn = 1
),
fotos_2025 AS (
    SELECT
        id_colaborador,
        nome,
        email,
        cargo,
        banda,
        l1_e,
        l2_e,
        l3_e,
        l4_e,
        l5_e,
        l6_e,
        l7_e,
        data_entrada,
        tenure,
        fechamento,
        pais
    FROM
        monthly_snapshots
    WHERE
        status = 'active'
)
SELECT DISTINCT
    f.fechamento,
    f.id_colaborador,
    f.nome,
    f.email,
    f.cargo,
    f.banda,
    f.pais,
    s.inicio_cargo,
    TIMESTAMPDIFF(
        MONTH,
        DATE_TRUNC('MONTH', s.inicio_cargo),
        DATE_TRUNC('MONTH', f.fechamento)
    ) AS tempo_no_cargo_em_meses,
    f.data_entrada AS dt_inicio_empresa,
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
    fotos_2025 AS f
INNER JOIN
    cargo_true_start AS s
        ON f.id_colaborador = s.id_colaborador
        AND f.cargo = s.cargo
WHERE
    f.l1_e = 'paulo.golgher@quintoandar.com.br'
ORDER BY
    f.nome ASC,
    f.fechamento ASC
