SELECT
    es.name AS nome,
    LOWER(es.work_email) AS email,
    es.job_name AS cargo,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    mh.name_l1 AS vp,
    LOWER(es.address_country) AS pais_onde_reside,
    bu.consolidated_business_unit_name AS empresa,
    es.band AS banda,
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END AS status,
    LOWER(es.termination_reason_name) AS motivo_desligamento,
    es.dt_terminated AS dt_desligamento,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS mh
        ON mh.assignment_number = es.assignment_number
        AND mh.is_current = TRUE
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
ORDER BY
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END,
    es.dt_terminated DESC
