-- Org Health employee roster, exported as S3 CSV.
-- Consumers: Base44 / S.A.R.A app and the Org Health Looker Studio dashboard.
-- Replaces the Daily Pipeline notebook dash_org_health.
WITH
absence_yesterday_ranked AS (
    SELECT
        far.person_number,
        dat.absence_type,
        far.dt_absence_ended,
        ROW_NUMBER() OVER (
            PARTITION BY far.person_number
            ORDER BY far.dt_absence_started DESC
        ) AS rn_absence
    FROM
        dw_time.fact_absence_requests AS far
    INNER JOIN
        dw_time.dim_absence_type AS dat
            ON far.sk_absence_type = dat.sk_absence_type
    WHERE
        far.dt_absence_started <= DATE_ADD(DATE_TRUNC('DAY', DATE('{load_end_date}')), -1)
        AND far.dt_absence_ended >= DATE_ADD(DATE_TRUNC('DAY', DATE('{load_end_date}')), -1)
        AND far.is_effective = TRUE
        AND far.is_valid = TRUE
),
absence_yesterday AS (
    SELECT
        person_number,
        absence_type,
        dt_absence_ended
    FROM
        absence_yesterday_ranked
    WHERE
        rn_absence = 1
),
current_year_performa AS (
    SELECT
        f.person_number,
        CASE
            WHEN f.performa_score = 'Outstanding' THEN 5
            WHEN f.performa_score = 'Above expectations' THEN 4
            WHEN f.performa_score = 'Meets expectations' THEN 3
            WHEN f.performa_score = 'Partially misses expectations' THEN 2
            WHEN f.performa_score = 'Insufficient' THEN 1
            ELSE -1
        END AS performa_score,
        cm.meeting_year AS performa_cycle,
        ROW_NUMBER() OVER (
            PARTITION BY f.person_number
            ORDER BY cm.meeting_year DESC
        ) AS rn_performa
    FROM
        dw_performance.fact_performance_calibrations AS f
    INNER JOIN
        dw_performance.dim_committee_meeting AS cm
            ON cm.sk_meeting = f.sk_committee_meeting
    INNER JOIN
        dw_performance.dim_cycle_period AS dcp
            ON dcp.sk_cycle_period = f.sk_cycle_period
            AND dcp.is_released = TRUE
    WHERE
        cm.meeting_year = YEAR(DATE('{load_start_date}'))
),
active_managers AS (
    SELECT DISTINCT
        LOWER(es.manager_assignment_number) AS id_gestor
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND LOWER(es.status) = 'active'
        AND es.manager_assignment_number IS NOT NULL
),
employee_roster AS (
    SELECT
        LOWER(es.assignment_number) AS id_colaborador,
        LOWER(es.name) AS nome,
        LOWER(es.work_email) AS email,
        es.band AS banda,
        LOWER(es.manager_assignment_number) AS id_gestor,
        LOWER(es.manager_name) AS gestor,
        LOWER(es.job_name) AS cargo,
        LOWER(es.job_family) AS classe_cargo,
        CONCAT(
            LOWER(es.cost_center_code),
            ' - ',
            SUBSTRING(LOWER(es.cost_center_name), 10)
        ) AS centro_de_custo,
        LOWER(NULLIF(es.owner_l1_name, '-1')) AS l1_cc,
        LOWER(NULLIF(es.owner_l2_name, '-1')) AS l2_cc,
        LOWER(NULLIF(es.owner_l3_name, '-1')) AS l3_cc,
        NULLIF(LOWER(es.vertical), '-1') AS vertical,
        NULLIF(LOWER(es.structure), '-1') AS structure,
        NULLIF(LOWER(es.team), '-1') AS team,
        COALESCE(es.count_direct_report, 0) AS diretos,
        es.hierarchy_depth AS layer,
        CASE
            WHEN es.is_manager = TRUE THEN 1
            ELSE 0
        END AS fl_lider,
        es.dt_employee_hired AS dt_inicio,
        es.dt_terminated AS dt_desligamento,
        CASE
            WHEN LOWER(es.termination_reason_name) IN ('desligamento involuntario', 'falecimento') THEN 'involuntario'
            WHEN LOWER(es.termination_reason_name) = 'desligamento voluntario' THEN 'voluntario'
            WHEN LOWER(es.termination_reason_name) = 'transferencia entre empresas' THEN 'transferencia'
            ELSE NULL
        END AS motivo_desligamento,
        COALESCE(LOWER(es.registered_sex), 'nao especificado') AS sexo,
        LOWER(es.name_l1) AS l1_gestor,
        LOWER(es.name_l2) AS l2_gestor,
        LOWER(es.name_l3) AS l3_gestor,
        LOWER(es.name_l4) AS l4_gestor,
        LOWER(es.name_l5) AS l5_gestor,
        LOWER(es.name_l6) AS l6_gestor,
        LOWER(es.name_l7) AS l7_gestor,
        LOWER(es.name_l8) AS l8_gestor,
        LOWER(es.name_l9) AS l9_gestor,
        es.person_number AS matricula,
        es.has_medical_disability_record,
        es.country,
        CAST(FROM_UTC_TIMESTAMP(es.ts_load, 'America/Sao_Paulo') AS DATE) AS dt_last_update
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND (
            LOWER(es.status) = 'active'
            OR EXISTS (
                SELECT
                    1
                FROM
                    active_managers AS am
                WHERE
                    am.id_gestor = LOWER(es.assignment_number)
            )
        )
)
SELECT
    employee_roster.id_colaborador,
    employee_roster.nome,
    employee_roster.email,
    employee_roster.banda,
    employee_roster.id_gestor,
    employee_roster.gestor,
    employee_roster.cargo,
    employee_roster.classe_cargo,
    employee_roster.centro_de_custo,
    employee_roster.l1_cc,
    employee_roster.l2_cc,
    employee_roster.l3_cc,
    employee_roster.vertical,
    employee_roster.structure,
    employee_roster.team,
    employee_roster.diretos,
    employee_roster.layer,
    employee_roster.fl_lider,
    employee_roster.dt_inicio,
    employee_roster.dt_desligamento,
    employee_roster.motivo_desligamento,
    employee_roster.sexo,
    employee_roster.l1_gestor,
    employee_roster.l2_gestor,
    employee_roster.l3_gestor,
    employee_roster.l4_gestor,
    employee_roster.l5_gestor,
    employee_roster.l6_gestor,
    employee_roster.l7_gestor,
    employee_roster.l8_gestor,
    employee_roster.l9_gestor,
    absence_yesterday.absence_type,
    absence_yesterday.dt_absence_ended,
    CASE
        WHEN employee_roster.has_medical_disability_record = TRUE THEN TRUE
        ELSE FALSE
    END AS is_pwd,
    current_year_performa.performa_score,
    current_year_performa.performa_cycle,
    employee_roster.country,
    employee_roster.dt_last_update
FROM
    employee_roster
LEFT JOIN
    absence_yesterday
        ON employee_roster.matricula = absence_yesterday.person_number
LEFT JOIN
    current_year_performa
        ON employee_roster.matricula = current_year_performa.person_number
        AND current_year_performa.rn_performa = 1
