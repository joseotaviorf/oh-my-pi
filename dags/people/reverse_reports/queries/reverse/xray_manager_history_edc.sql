-- Manager history for X-Ray / Employee Data Center AppSheet.
-- Org context from reverse_reports.xray_general_info (same DAG; see inner_dependencies in declaration). DBP-1447.
WITH employee_context AS (
    SELECT
        gi.matricula,
        gi.status AS Employee_status,
        gi.nome,
        gi.email,
        gi.gestor AS gestor_atual,
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
manager_timeline AS (
    SELECT
        LOWER(es.assignment_number) AS id_colaborador,
        es.person_number AS matricula,
        INITCAP(es.name) AS nome,
        LOWER(es.manager_name) AS gestor,
        es.dt_month_reference,
        -- Gaps-and-islands: a new stint starts whenever the manager identifier changes
        -- from the previous month for the same assignment, so a manager who returns
        -- after a different manager gets a separate period instead of merging into one.
        SUM(
            CASE
                WHEN COALESCE(
                        es.manager_assignment_number,
                        es.manager_work_email,
                        es.manager_name
                    )
                    = LAG(
                        COALESCE(
                            es.manager_assignment_number,
                            es.manager_work_email,
                            es.manager_name
                        )
                    ) OVER (
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
        AND (
            es.manager_assignment_number IS NOT NULL
            OR es.manager_work_email IS NOT NULL
            OR es.manager_name IS NOT NULL
        )
),
manager_history AS (
    SELECT
        id_colaborador,
        matricula,
        MAX(nome) AS nome,
        MAX(gestor) AS gestor,
        MIN(dt_month_reference) AS data_inicio_gestor,
        MAX(dt_month_reference) AS data_fim_gestor
    FROM
        manager_timeline
    GROUP BY
        id_colaborador,
        matricula,
        stint_group
)
SELECT
    mh.id_colaborador,
    COALESCE(ec.nome, mh.nome) AS nome,
    ec.gestor_atual,
    ec.email,
    ec.Employee_status,
    mh.gestor,
    ec.empresa,
    ec.vertical,
    ec.structure,
    ec.business,
    ec.product,
    ec.banda,
    ec.primary_team_tech_exclusive,
    ec.L1,
    ec.L2,
    ec.L3,
    ec.L4,
    ec.L5,
    ec.L6,
    ec.L7,
    mh.data_inicio_gestor,
    mh.data_fim_gestor,
    ec.access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    manager_history AS mh
LEFT JOIN
    employee_context AS ec
        ON mh.matricula = ec.matricula
