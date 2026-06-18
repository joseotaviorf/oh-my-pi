SELECT
    es.name AS nome,
    LOWER(es.work_email) AS email,
    bu.consolidated_business_unit_name AS empresa,
    es.job_family AS classe_cargo,
    CASE
        WHEN es.is_manager IS TRUE THEN 'lider'
        ELSE 'individual contributor'
    END AS lideranca,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    NULLIF(es.owner_l1_name, '-1') AS l1_cc,
    NULLIF(es.owner_l2_name, '-1') AS l2_cc,
    NULLIF(es.owner_l3_name, '-1') AS l3_cc,
    NULLIF(LOWER(es.vertical), '-1') AS vertical,
    NULLIF(LOWER(es.structure), '-1') AS structure,
    NULLIF(LOWER(es.team), '-1') AS team,
    NULLIF(LOWER(es.business), '-1') AS business,
    NULLIF(LOWER(es.product), '-1') AS product,
    NULLIF(LOWER(es.brand), '-1') AS brand,
    NULLIF(LOWER(es.chapter), '-1') AS chapter,
    NULLIF(LOWER(es.line), '-1') AS line,
    mh.name_l0 AS l0_gestor,
    mh.name_l1 AS l1_gestor,
    mh.name_l2 AS l2_gestor,
    mh.name_l3 AS l3_gestor,
    mh.name_l4 AS l4_gestor,
    mh.name_l5 AS l5_gestor,
    mh.name_l6 AS l6_gestor,
    mh.name_l7 AS l7_gestor,
    mh.name_l8 AS l8_gestor,
    CAST(NULL AS STRING) AS tribo_time,
    CAST(NULL AS STRING) AS squad,
    CAST(NULL AS STRING) AS linha,
    CAST(NULL AS STRING) AS tipo_de_linha,
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
    es.dt_reference = CURRENT_DATE()
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND es.is_active = TRUE
