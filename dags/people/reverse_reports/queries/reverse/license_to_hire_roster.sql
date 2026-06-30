WITH
    license_base AS (
        SELECT
            es.person_number,
            es.name,
            LOWER(es.work_email) AS email,
            es.dt_hired,
            es.band,
            LOWER(es.country) AS pais,
            NULLIF(es.owner_l1_name, '-1') AS l1_cc,
            NULLIF(es.owner_l2_name, '-1') AS l2_cc,
            NULLIF(es.owner_l3_name, '-1') AS l3_cc,
            CASE
                WHEN LOWER(es.status) = 'active' THEN 'ativo'
                WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
                ELSE LOWER(es.status)
            END AS status,
            CASE
                WHEN es.is_manager IS TRUE THEN 1
                ELSE 0
            END AS fl_lider,
            NULLIF(LOWER(es.structure), '-1') AS structure,
            NULLIF(LOWER(es.vertical), '-1') AS vertical,
            FLOOR(MONTHS_BETWEEN(LAST_DAY(DATE('{load_start_date}')), es.dt_hired)) AS tenure_meses
        FROM
            metric_people.employee_snapshots AS es
        WHERE
            es.is_current = TRUE
            AND es.is_primary_assignment_for_snapshot = TRUE
            AND (
                es.dt_terminated IS NULL
                OR es.dt_terminated >= DATE('2025-01-01')
            )
    )
SELECT
    lb.person_number AS matricula,
    lb.tenure_meses,
    CONCAT(
        CASE
            WHEN lb.fl_lider = 0
                AND CAST(lb.band AS INT) >= 7
                AND lb.tenure_meses < 4 THEN 'onboarding ic'
            WHEN lb.fl_lider = 0
                AND CAST(lb.band AS INT) >= 7
                AND lb.tenure_meses >= 4 THEN 'eligible ic'
            WHEN lb.fl_lider = 1
                AND CAST(lb.band AS INT) >= 7 THEN 'eligible managers'
            WHEN lb.structure = 'people' THEN 'people'
        END,
        CASE
            WHEN lb.vertical = 'tech' THEN ' - tech'
            ELSE ''
        END
    ) AS grupo,
    lb.name AS nome,
    lb.email,
    lb.dt_hired AS dt_inicio,
    lb.band,
    lb.pais,
    lb.l1_cc,
    lb.l2_cc,
    lb.l3_cc,
    lb.status,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    license_base AS lb
ORDER BY
    grupo DESC,
    dt_inicio
