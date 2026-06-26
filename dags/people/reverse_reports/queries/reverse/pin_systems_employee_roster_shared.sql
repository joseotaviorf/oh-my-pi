SELECT
    es.business_unit_name AS empresa,
    es.address_country AS `país`,
    es.person_number,
    es.name AS nome,
    CASE
        WHEN es.is_active = TRUE THEN 'ACTIVE'
        ELSE 'INACTIVE'
    END AS status,
    es.dt_hired AS dt_inicio,
    LOWER(es.work_email) AS email,
    es.manager_name AS gestor,
    es.job_code AS cod_cargo,
    es.job_name AS cargo,
    es.job_family AS classe_cargo,
    es.band AS banda,
    LOWER(es.cost_center_code) AS numero_centro_de_custo,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
ORDER BY
    CASE
        WHEN es.is_active = TRUE THEN 0
        ELSE 1
    END,
    es.sk_hired_date DESC
