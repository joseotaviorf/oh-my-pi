SELECT
    bu.consolidated_business_unit_name AS empresa,
    es.name AS nome,
    es.person_number AS person_number,
    LOWER(es.work_email) AS email,
    es.band AS banda,
    es.manager_name AS gestor,
    LOWER(es.manager_work_email) AS email_gestor,
    es.job_name AS cargo,
    es.job_family AS classe_cargo,
    LOWER(es.hrbp_work_email) AS hrbp,
    es.count_direct_report AS diretos,
    es.count_total_report AS diretos_e_indiretos,
    LOWER(es.address_state) AS estado,
    LOWER(es.address_city) AS cidade,
    CASE
        WHEN es.is_member_lt IS TRUE THEN 1
        ELSE 0
    END AS fl_lt,
    es.dt_hired AS dt_inicio,
    es.gender_identity AS identidade_genero,
    LOWER(es.registered_sex) AS sexo,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.sk_business_unit
WHERE
    es.dt_reference = CURRENT_DATE()
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND LOWER(es.status) = 'active'
    AND CAST(es.band AS INT) >= 10
