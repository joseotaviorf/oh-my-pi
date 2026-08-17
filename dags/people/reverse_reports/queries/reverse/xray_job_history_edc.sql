-- Job (cargo) history for X-Ray / Employee Data Center AppSheet.
-- Org context from reverse_reports.xray_general_info (same DAG; see inner_dependencies in declaration). DBP-1447.
WITH employee_context AS (
    SELECT
        gi.id_colaborador,
        gi.matricula,
        gi.status AS Employee_status,
        gi.nome,
        gi.email,
        gi.gestor,
        gi.empresa,
        gi.vertical,
        gi.structure,
        gi.business,
        gi.product,
        gi.banda,
        gi.primary_team_tech_exclusive,
        gi.L1,
        gi.L2,
        gi.L3,
        gi.L4,
        gi.L5,
        gi.L6,
        gi.L7,
        gi.access_list
    FROM
        reverse_reports.xray_general_info AS gi
    WHERE
        gi.year = YEAR(DATE('{load_start_date}'))
        AND gi.month = MONTH(DATE('{load_start_date}'))
        AND gi.day = DAY(DATE('{load_start_date}'))
),
job_timeline AS (
    SELECT
        LOWER(es.assignment_number) AS id_colaborador,
        es.person_number AS matricula,
        INITCAP(es.name) AS nome,
        INITCAP(es.job_name) AS cargo,
        es.dt_month_reference,
        -- Gaps-and-islands: a new stint starts whenever the job name changes
        -- from the previous month for the same assignment, so a job revisited
        -- later gets a separate period instead of merging into one.
        SUM(
            CASE
                WHEN es.job_name
                    = LAG(es.job_name) OVER (
                        PARTITION BY LOWER(es.assignment_number)
                        ORDER BY es.dt_month_reference
                    )
                    THEN 0
                ELSE 1
            END
        ) OVER (
            PARTITION BY LOWER(es.assignment_number)
            ORDER BY es.dt_month_reference
        ) AS stint_group
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_primary_assignment_for_snapshot = TRUE
        AND es.job_name IS NOT NULL
),
job_history AS (
    SELECT
        id_colaborador,
        matricula,
        MAX(nome) AS nome,
        MAX(cargo) AS cargo,
        MIN(dt_month_reference) AS data_inicio_cargo,
        MAX(dt_month_reference) AS data_fim_cargo
    FROM
        job_timeline
    GROUP BY
        id_colaborador,
        matricula,
        stint_group
)
SELECT
    jh.id_colaborador,
    COALESCE(ec.nome, jh.nome) AS nome,
    ec.email,
    ec.gestor,
    ec.Employee_status,
    jh.cargo,
    ec.empresa,
    ec.vertical,
    ec.structure,
    ec.business,
    ec.product,
    ec.banda,
    ec.primary_team_tech_exclusive,
    jh.data_inicio_cargo,
    jh.data_fim_cargo,
    ec.L1,
    ec.L2,
    ec.L3,
    ec.L4,
    ec.L5,
    ec.L6,
    ec.L7,
    ec.access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    job_history AS jh
LEFT JOIN
    employee_context AS ec
        ON jh.matricula = ec.matricula
