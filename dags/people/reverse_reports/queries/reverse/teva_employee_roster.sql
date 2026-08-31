-- Active-employee roster with leadership-chain access list for the TEVA questionnaire workbook.
SELECT
    LOWER(es.assignment_number) AS id_colaborador,
    LOWER(es.work_email) AS email,
    es.name AS nome,
    CASE
        WHEN CAST(es.band AS INT) >= 10 THEN 'Team leader'
    END AS role,
    LOWER(COALESCE(es.hrbp_work_email, cc_current.hrbp_work_email)) AS hrbp,
    NULLIF(LOWER(es.vertical), '-1') AS vertical,
    NULLIF(LOWER(es.structure), '-1') AS structure,
    es.consolidated_business_unit_name AS empresa,
    CASE LOWER(es.country)
        WHEN 'brazil' THEN 'brasil'
        WHEN 'ecuador' THEN 'equador'
        WHEN 'uruguay' THEN 'uruguai'
        ELSE LOWER(es.country)
    END AS pais,
    es.job_name AS cargo,
    CONCAT_WS(
        ',',
        LOWER(COALESCE(mh.email_l0, 'gbraga@quintoandar.com.br')),
        LOWER(mh.email_l1),
        LOWER(mh.email_l2),
        LOWER(mh.email_l3),
        LOWER(mh.email_l4),
        LOWER(mh.email_l5),
        LOWER(mh.email_l6),
        LOWER(mh.email_l7),
        LOWER(mh.email_l8),
        LOWER(mh.email_l9)
    ) AS access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON cc.sk_cost_center_version = es.sk_cost_center_version
LEFT JOIN
    dw_organization.dim_cost_center AS cc_current
        ON cc_current.id_organization = cc.id_organization
        AND cc_current.is_current = TRUE
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS mh
        ON mh.assignment_number = es.assignment_number
        AND mh.is_current = TRUE
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND LOWER(es.status) = 'active'
