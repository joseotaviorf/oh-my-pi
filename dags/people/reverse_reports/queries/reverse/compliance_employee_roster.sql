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
    es.manager_name AS gestor,
    LOWER(es.manager_work_email) AS email_gestor,
    mh.name_l2 AS l2_gestor,
    LOWER(mh.email_l2) AS email_l2,
    cc.hrbp_name AS nome_hrbp,
    LOWER(cc.hrbp_work_email) AS email_hrbp,
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
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON cc.sk_cost_center_version = es.sk_cost_center_version
WHERE
    es.is_current_for_employee = TRUE
ORDER BY
    CASE
        WHEN LOWER(es.status) = 'active' THEN 'ativo'
        WHEN LOWER(es.status) = 'terminated' THEN 'desligado'
        ELSE LOWER(es.status)
    END,
    es.dt_terminated DESC
