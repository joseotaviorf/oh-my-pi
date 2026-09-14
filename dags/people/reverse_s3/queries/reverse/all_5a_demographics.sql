-- Active All 5A employee demographics for the Rituals app, exported as S3 CSV.
SELECT
    es.name AS nome,
    LOWER(es.work_email) AS email,
    es.manager_name AS gestor,
    es.job_family AS classe_cargo,
    es.band AS banda,
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
    es.name_l4 AS l4_gestor,
    es.name_l5 AS l5_gestor,
    es.name_l6 AS l6_gestor,
    es.name_l7 AS l7_gestor,
    es.consolidated_business_unit_name AS empresa,
    CASE
        WHEN es.is_manager IS TRUE THEN 1
        ELSE 0
    END AS fl_lider,
    es.access_list AS access_list
FROM
    metric_people.employee_snapshots AS es
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND LOWER(es.status) = 'active'
