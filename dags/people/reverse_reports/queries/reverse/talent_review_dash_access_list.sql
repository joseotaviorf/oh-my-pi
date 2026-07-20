-- Talent Review Looker access-list feed (PDS / base_analytics tab).
SELECT
    CAST(es.person_number AS STRING) AS `Número de Pessoa`,
    LOWER(es.hrbp_work_email) AS hrbp,
    LOWER(es.name_l1) AS l1_gestor,
    LOWER(es.name_l2) AS l2_gestor,
    LOWER(es.name_l3) AS l3_gestor,
    LOWER(es.name_l4) AS l4_gestor,
    LOWER(es.name_l5) AS l5_gestor,
    LOWER(es.name_l6) AS l6_gestor,
    es.access_list_no_employee_no_hrbp AS access_list,
    LOWER(es.manager_name) AS gestor_pin,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
WHERE
    es.is_current_for_employee = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
