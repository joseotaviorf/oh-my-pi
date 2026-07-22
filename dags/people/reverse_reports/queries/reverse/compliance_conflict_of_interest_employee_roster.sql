-- Active employees plus terminated in the last 6 months for Compliance
-- conflict-of-interest checks (supplier registration / homologation).
WITH
    conflict_of_interest_rows AS (
        SELECT
            es.name AS nome,
            LOWER(es.country) AS pais,
            es.cpf,
            es.job_name AS cargo,
            es.band AS banda,
            CONCAT(
                LOWER(es.cost_center_code),
                ' - ',
                SUBSTRING(LOWER(es.cost_center_name), 10)
            ) AS centro_de_custo,
            CASE
                WHEN LOWER(es.status) = 'terminated'
                    AND es.dt_terminated <= DATE('{load_start_date}')
                THEN es.dt_terminated
            END AS dt_desligamento,
            CASE
                WHEN LOWER(es.status) = 'terminated'
                    AND es.dt_terminated <= DATE('{load_start_date}')
                THEN es.termination_category
            END AS motivo_desligamento,
            ROW_NUMBER() OVER (
                PARTITION BY
                    es.person_number
                ORDER BY
                    CASE
                        WHEN LOWER(es.status) = 'active' THEN 0
                        ELSE 1
                    END,
                    es.assignment_number DESC
            ) AS rn
        FROM
            metric_people.employee_snapshots AS es
        WHERE
            es.is_current_for_employee = TRUE
            AND (
                LOWER(es.status) = 'active'
                OR (
                    LOWER(es.status) = 'terminated'
                    AND es.dt_terminated >= ADD_MONTHS(DATE('{load_start_date}'), -6)
                )
            )
    )
SELECT
    nome,
    pais,
    cpf,
    cargo,
    banda,
    centro_de_custo,
    motivo_desligamento,
    dt_desligamento,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    conflict_of_interest_rows
WHERE
    rn = 1
