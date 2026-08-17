-- Talent review history for X-Ray / Employee Data Center AppSheet.
-- ciclo/ratings replicate the retired sandbox talent_review_history CTAS: fact_talent_reviews
-- joined to dim_committee_meeting/dim_cycle_period/dim_talent_rating; email_avaliador resolves
-- the evaluator's manager via dim_management_hierarchy + fact_assignment_snapshots as of the
-- committee meeting date (point-in-time, not the current manager). DBP-1447.
-- Org context from reverse_reports.xray_general_info (same DAG; see inner_dependencies in declaration).
WITH talent_review AS (
    SELECT
        ftr.person_number,
        CONCAT(
            YEAR(TO_DATE(CAST(ftr.sk_committee_meeting_date AS STRING), 'yyyyMMdd')),
            '-',
            dcm.reference_period
        ) AS ciclo,
        dtr.potential AS potencial,
        dtr.criticality AS criticidade,
        dtr.readiness AS prontidao,
        dtr.risk_of_loss AS risco_de_perda,
        de_mgr.work_email AS email_avaliador
    FROM
        dw_performance.fact_talent_reviews AS ftr
    INNER JOIN
        dw_performance.dim_committee_meeting AS dcm
            ON dcm.sk_meeting = ftr.sk_committee_meeting
    INNER JOIN
        dw_performance.dim_cycle_period AS dcp
            ON dcp.sk_cycle_period = ftr.sk_cycle_period
            AND dcp.is_released = TRUE
    LEFT JOIN
        dw_performance.dim_talent_rating AS dtr
            ON dtr.sk_talent_rating = ftr.sk_talent_rating_from_calibration
    LEFT JOIN
        dw_employee_details.fact_assignment_snapshots AS fas
            ON fas.assignment_number = ftr.assignment_number
            AND fas.dt_reference = TO_DATE(CAST(ftr.sk_committee_meeting_date AS STRING), 'yyyyMMdd')
    LEFT JOIN
        dw_employee_details.dim_management_hierarchy AS dmh
            ON dmh.sk_hierarchy_version = fas.sk_hierarchy_version
    LEFT JOIN
        dw_employee_details.fact_assignment_snapshots AS fas_mgr
            ON fas_mgr.assignment_number = dmh.manager_assignment_number
            AND fas_mgr.dt_reference = fas.dt_reference
    LEFT JOIN
        dw_employee_details.dim_employee AS de_mgr
            ON de_mgr.person_number = fas_mgr.person_number
    WHERE
        ftr.person_number IS NOT NULL
        AND ftr.is_latest_for_employee_in_cycle = TRUE
),
employee_context AS (
    SELECT
        gi.id_colaborador,
        gi.matricula,
        gi.status AS Employee_status,
        gi.nome,
        gi.email,
        gi.gestor,
        gi.centro_de_custo,
        gi.empresa,
        gi.vertical,
        gi.structure,
        gi.team,
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
)
SELECT
    UPPER(t.ciclo) AS ciclo,
    ec.id_colaborador,
    ec.nome,
    ec.Employee_status,
    ec.email,
    ec.gestor,
    t.email_avaliador,
    INITCAP(t.prontidao) AS prontidao,
    INITCAP(t.risco_de_perda) AS risco_de_perda,
    INITCAP(t.potencial) AS potencial,
    INITCAP(t.criticidade) AS criticidade,
    ec.centro_de_custo,
    ec.empresa,
    ec.vertical,
    ec.structure,
    ec.team,
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
    ec.access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    talent_review AS t
LEFT JOIN
    employee_context AS ec
        ON t.person_number = ec.matricula
