-- Exception: cycle scores/comments still sourced from sandbox performance_review_history for AppSheet label parity (letter-prefixed faixa/impacto). DBP-1447.
-- Performance review history for X-Ray / Employee Data Center AppSheet (Performa EDC).
-- Org context from reverse_reports.xray_general_info (same DAG; see inner_dependencies in declaration).
WITH employee_context AS (
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
    p.ciclo,
    ec.id_colaborador,
    ec.Employee_status,
    ec.nome,
    ec.email,
    ec.gestor,
    INITCAP(p.impacto) AS impacto,
    INITCAP(p.comportamento) AS comportamento,
    INITCAP(p.lideranca) AS lideranca,
    INITCAP(p.faixa_de_distribuicao) AS faixa_de_distribuicao,
    p.email_avaliador,
    p.comentario_gestor,
    ec.centro_de_custo,
    ec.empresa,
    ec.vertical,
    ec.structure,
    ec.team,
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
    datalake_people_analytics_sandbox.performance_review_history AS p
LEFT JOIN
    employee_context AS ec
        ON p.person_number = ec.matricula
