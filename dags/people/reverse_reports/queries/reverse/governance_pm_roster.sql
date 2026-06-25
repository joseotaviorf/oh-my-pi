SELECT
    es.name AS nome,
    LOWER(es.work_email) AS email,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    es.band AS banda,
    es.manager_name AS gestor,
    es.job_name AS cargo,
    es.job_family AS classe_cargo,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    NULLIF(LOWER(es.structure), '-1') AS structure,
    bu.consolidated_business_unit_name AS empresa,
    es.dt_hired AS dt_inicio,
    es.name_l1 AS l1_gestor,
    es.name_l2 AS l2_gestor,
    es.name_l3 AS l3_gestor,
    LOWER(es.address_city) AS residencia_cidade,
    LOWER(es.country) AS pais,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND LOWER(es.status) = 'active'
    AND (
        LOWER(es.name_l1) = 'deborah leticia gouveia abi saber'
        OR LOWER(es.name) = 'deborah leticia gouveia abi saber'
    )
