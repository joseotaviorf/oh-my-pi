-- Active All 5A employee demographics for the Rituals app (tab ALL5A1).
SELECT
    es.name AS nome,
    LOWER(es.work_email) AS email,
    es.manager_name AS gestor,
    es.job_family AS classe_cargo,
    CONCAT(
        LOWER(es.cost_center_code),
        ' - ',
        SUBSTRING(LOWER(es.cost_center_name), 10)
    ) AS centro_de_custo,
    NULLIF(LOWER(es.structure), '-1') AS structure,
    LOWER(es.country) AS pais,
    LOWER(es.address_state) AS residencia_uf,
    LOWER(es.address_city) AS residencia_cidade,
    es.name_l0 AS l0_gestor,
    es.name_l1 AS l1_gestor,
    es.name_l2 AS l2_gestor,
    es.name_l3 AS l3_gestor,
    es.consolidated_business_unit_name AS empresa,
    CASE
        WHEN es.is_manager IS TRUE THEN 1
        ELSE 0
    END AS fl_lider,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND LOWER(es.status) = 'active'
