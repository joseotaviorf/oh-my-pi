-- Active Brazil employees for the PwD HUB roster (status, disability flag, L1/L2 managers).
SELECT
    LOWER(es.assignment_number) AS id_colaborador,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    CASE
        WHEN dis.is_active = TRUE THEN 'sim'
        ELSE 'nao'
    END AS pcd_laudo,
    LOWER(es.name_l1) AS l1_gestor,
    LOWER(es.name_l2) AS l2_gestor,
    CASE
        WHEN LOWER(es.country) = 'brazil' THEN 'brasil'
        ELSE LOWER(es.country)
    END AS pais,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_demographics.dim_employee_disability AS dis
        ON dis.sk_employee = es.sk_employee
        AND dis.is_primary = TRUE
        AND DATE('{load_start_date}') >= dis.dt_valid_from
        AND DATE('{load_start_date}') <= dis.dt_valid_to
WHERE
    es.is_current_for_employee = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND LOWER(es.status) = 'active'
    AND LOWER(es.country) = 'brazil'
