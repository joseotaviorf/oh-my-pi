-- Current-month band tenure for Tech HRBPs (Paulo + Rafael L1 scopes).
WITH monthly_snapshots AS (
    SELECT
        es.dt_month_reference AS fechamento,
        es.person_number,
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
        es.months_tenure_in_company AS tempo_de_casa,
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
        banda,
        MIN(fechamento) AS inicio_banda
    FROM
        monthly_snapshots
    GROUP BY
        person_number,
        banda
),
fotos_2025 AS (
    SELECT
        person_number,
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
        tempo_de_casa,
        fechamento,
        pais
    FROM
        monthly_snapshots
    WHERE
        status = 'active'
        AND l1_e IN (
            'paulo.golgher@quintoandar.com.br',
            'rafael.castro@quintoandar.com.br'
        )
),
base_fotos AS (
    SELECT
        f.fechamento,
        f.person_number,
        f.nome,
        f.email,
        f.cargo,
        f.banda,
        f.pais,
        s.inicio_banda,
        CASE
            WHEN (
                f.pais IN ('argentina', 'mexico')
                AND s.inicio_banda <= DATE '2024-10-01'
            ) THEN TIMESTAMPDIFF(
                MONTH,
                DATE_TRUNC('MONTH', DATE '2024-10-01'),
                DATE_TRUNC('MONTH', f.fechamento)
            )
            ELSE TIMESTAMPDIFF(
                MONTH,
                DATE_TRUNC('MONTH', s.inicio_banda),
                DATE_TRUNC('MONTH', f.fechamento)
            )
        END AS tempo_na_banda_em_meses,
        f.data_entrada AS dt_inicio_empresa,
        f.tempo_de_casa,
        f.l1_e,
        f.l2_e,
        f.l3_e,
        f.l4_e,
        f.l5_e,
        f.l6_e,
        f.l7_e
    FROM
        fotos_2025 AS f
    INNER JOIN
        band_start_dates AS s
            ON f.person_number = s.person_number
            AND f.banda = s.banda
),
latest_fechamento AS (
    SELECT
        MAX(fechamento) AS fechamento
    FROM
        base_fotos
)
SELECT DISTINCT
    bf.fechamento,
    bf.person_number,
    bf.nome,
    bf.email,
    bf.cargo,
    bf.banda,
    bf.pais,
    bf.inicio_banda,
    bf.tempo_na_banda_em_meses,
    bf.dt_inicio_empresa,
    bf.tempo_de_casa,
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
    base_fotos AS bf
INNER JOIN
    latest_fechamento AS lf
        ON bf.fechamento = lf.fechamento
ORDER BY
    bf.nome ASC,
    bf.fechamento ASC
