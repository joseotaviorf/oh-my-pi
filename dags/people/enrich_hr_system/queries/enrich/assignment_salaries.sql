WITH
    salaries_cte AS (
        SELECT
            s.id_assignment,
            s.currency_code,
            s.salary_amount,
            s.dt_from AS dt_salary_started,
            s.dt_to,
            LEAD (s.dt_from, 1) OVER (
                PARTITION BY
                    id_assignment
                ORDER BY
                    s.dt_from
            ) AS next_dt_salary_started,
            CASE
                WHEN dt_to + 1 <> next_dt_salary_started
                AND next_dt_salary_started IS NOT NULL THEN next_dt_salary_started - 1
                ELSE dt_to
            END AS dt_salary_ended,
            s.action_reason,
            CASE s.action_reason
                WHEN "Dissídio / Acordo Coletivo" THEN "Dissídio"
                WHEN "Contratar" THEN "Contratação"
                WHEN "Dissídio / Convenção Coletiva" THEN "Dissídio"
                WHEN "Outros Casos" THEN "Outros"
                WHEN "Readmitir para preencher posição vaga" THEN "Readmissão"
                WHEN "Salário Mínimo" THEN "Enquadramento"
                WHEN "Efetivação de Estagiário ou Aprendiz" THEN "Efetivação"
                WHEN "Movimentação de Centro de Custo" THEN "Outros"
                WHEN "Reorganização" THEN "Alteração de Função"
                WHEN "Futura contratação para preencher posição vaga" THEN "Contratação"
                WHEN "1º Emprego" THEN "Contratação"
            ELSE s.action_reason
            END AS standardized_action_reason
        FROM
            datalake_hr_system_clean.salaries AS s
    )
SELECT
    a.id_person,
    a.id_assignment,
    a.id_period_of_service,
    a.assignment_name,
    a.band,
    a.cost_center_name,
    s.action_reason,
    s.standardized_action_reason,
    s.currency_code,
    s.grade_name,
    s.adjustment_amount,
    s.adjustment_percentage,
    s.compa_ratio,
    s.salary_range_mid_point,
    LAG(salary_amount) OVER (
      PARTITION BY s.id_assignment
      ORDER BY
        s.dt_salary_started
    ) AS last_currency_code,
    s.salary_amount,
    LAG(s.salary_amount) OVER (
        PARTITION BY s.id_assignment
        ORDER BY
        s.dt_salary_started
    ) AS last_salary_amount,
    CASE WHEN
        last_currency_code = currency_code
        THEN 100 *(salary_amount / last_salary_amount - 1)
        ELSE 0
    END AS percentage_increase,
    a.dt_effective_start AS dt_assignment_started,
    a.dt_effective_end AS dt_assignment_ended,
    s.dt_salary_started,
    s.dt_salary_ended,
    LAG(s.dt_salary_started) OVER (
        PARTITION BY s.id_assignment
        ORDER BY
            s.dt_salary_started
    ) AS dt_last_salary_started,
    LAG(s.dt_salary_ended) OVER (
        PARTITION BY s.id_assignment
        ORDER BY
            s.dt_salary_ended
    ) AS dt_last_salary_ended
FROM
    datalake_hr_system.assignments AS a
FULL OUTER JOIN
    salaries_cte AS s
        ON s.id_assignment = a.id_assignment
        AND (
            dt_salary_started BETWEEN dt_effective_start AND dt_effective_end
            OR dt_salary_ended BETWEEN dt_effective_start AND dt_effective_end
            OR dt_effective_start BETWEEN dt_salary_started AND dt_salary_ended
            OR dt_effective_end BETWEEN dt_salary_started AND dt_salary_ended
        )
WHERE
    a.assignment_status_type = 'ACTIVE'
