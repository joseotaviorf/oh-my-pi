-- Active employee org/management-hierarchy roster, exported as a single S3
-- CSV object under allocationtool/import/.
-- Consumer: Allocation Tool app (pulls its import data from this export).
SELECT
    es.person_number AS matricula,
    es.name AS nome,
    es.work_email AS email,
    'ativo' AS status,
    es.manager_name AS gestor,
    es.job_name AS cargo,
    es.vertical AS vertical,
    es.structure AS structure,
    es.team AS team,
    es.chapter AS chapter,
    COALESCE(es.name_l0, 'gabriel braga vieira') AS l0_gestor,
    es.name_l1 AS l1_gestor,
    es.name_l2 AS l2_gestor,
    es.name_l3 AS l3_gestor,
    es.name_l4 AS l4_gestor,
    es.name_l5 AS l5_gestor,
    es.name_l6 AS l6_gestor,
    es.name_l7 AS l7_gestor,
    es.name_l8 AS l8_gestor,
    CASE
        WHEN es.is_manager IS TRUE THEN 1
        ELSE 0
    END AS fl_lider,
    es.ts_load AS ts_load
FROM
    metric_people.employee_snapshots AS es
WHERE
    es.is_current_for_employee = TRUE
    AND (es.dt_terminated IS NULL OR es.dt_terminated >= DATE('{load_start_date}'))
    AND es.dt_assignment_started <= DATE('{load_start_date}')
    AND (LOWER(es.work_email) NOT LIKE '%@ext.%' OR es.work_email IS NULL)
ORDER BY
    es.name
