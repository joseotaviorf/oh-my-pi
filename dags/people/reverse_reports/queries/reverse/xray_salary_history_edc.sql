-- Salary adjustment history for X-Ray / Employee Data Center AppSheet.
-- Org context from reverse_reports.xray_general_info (same DAG; see inner_dependencies in declaration). DBP-1447.
WITH employee_context AS (
    SELECT
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
)
SELECT
    fc.dt_valid_from AS dt_from,
    CASE
        WHEN fc.dt_valid_to IS NULL
            OR fc.dt_valid_to >= DATE('9999-12-31')
        THEN DATE('{load_start_date}')
        ELSE fc.dt_valid_to
    END AS dt_to,
    ec.nome,
    ec.email,
    ec.gestor,
    ec.Employee_status,
    LOWER(fc.assignment_number) AS assignment_number,
    CASE
        WHEN ded.reason_name_ptb IN (
            'Contratar',
            'Dissídio / Acordo Coletivo',
            'Dissídio / Convenção Coletiva'
        ) THEN ded.reason_name_ptb
        WHEN ded.reason_name_ptb = 'Mérito' THEN 'Merit'
        WHEN ded.reason_name_ptb = 'Correção' THEN 'Correction'
        WHEN ded.reason_name_ptb = '1º Emprego' THEN 'Hire'
        WHEN ded.reason_name_ptb = 'Promoção' THEN 'Promotion'
        WHEN ded.reason_name_ptb = 'Movimentação Internacional' THEN 'International Transfer'
        WHEN ded.reason_name_ptb = 'Futura contratação para preencher posição vaga' THEN 'Future Hire for Vacant Position'
        WHEN ded.reason_name_ptb = 'Alteração de Função' THEN 'Role Change'
        WHEN ded.reason_name_ptb = 'Outros Casos' THEN 'Other Cases'
        WHEN ded.reason_name_ptb = 'Admissão Internacional' THEN 'International Hire'
        WHEN ded.reason_name_ptb = 'Reorganização' THEN 'Reorganization'
        WHEN ded.reason_name_ptb = 'Enquadramento' THEN 'Salary Alignment (Enquadramento)'
        WHEN ded.reason_name_ptb = 'Efetivação de Estagiário ou Aprendiz' THEN 'Intern/Apprentice Efectivation'
        WHEN ded.reason_name_ptb = 'Salário Mínimo' THEN 'Minimum Wage'
        WHEN ded.reason_name_ptb = 'Movimentação de Centro de Custo' THEN 'Cost Center Change'
        WHEN ded.reason_name_ptb = 'Recrutamento Interno' THEN 'Internal Recruitment'
        WHEN ded.reason_name_ptb = 'Readmitir para preencher posição vaga' THEN 'Rehire for Vacant Position'
        WHEN ded.reason_name IS NOT NULL AND LENGTH(TRIM(ded.reason_name)) > 0 THEN ded.reason_name
        ELSE ded.reason_name_ptb
    END AS action_reason_translated,
    fc.amount_adjustment AS adjustment_amount,
    fc.pct_adjustment / 100.0 AS adjustment_percentage,
    fc.amount_salary AS salary_amount,
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
    ec.access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    dw_compensation.fact_compensations AS fc
LEFT JOIN
    dw_compensation.dim_event_definition AS ded
        ON fc.sk_event_definition = ded.sk_event_definition
LEFT JOIN
    employee_context AS ec
        ON fc.person_number = ec.matricula
WHERE
    (
        (
            fc.amount_adjustment > 0
            AND (
                fc.pct_adjustment IS NULL
                OR fc.pct_adjustment >= 1
            )
        )
        OR ded.reason_name_ptb = 'Contratar'
    )
