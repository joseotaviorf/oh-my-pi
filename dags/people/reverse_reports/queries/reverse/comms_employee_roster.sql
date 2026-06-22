SELECT
    bu.consolidated_business_unit_name AS empresa,
    es.person_number AS person_number,
    es.name AS nome,
    LOWER(es.work_email) AS email,
    es.band AS banda,
    CASE
        WHEN es.is_member_lt IS TRUE THEN 1
        ELSE 0
    END AS flag_LT,
    es.dt_hired AS dt_inicio,
    CASE
        -- Legacy base_comms: 7-day new-hire window measured from D-1 (snapshot batch date).
        -- DATE_SUB(dt_reference, 1) then 7 days back equals DATE_SUB(CURRENT_DATE(), 8) here.
        WHEN es.dt_hired > DATE_SUB(DATE_SUB(es.dt_reference, 1), 7) THEN 1
        ELSE 0
    END AS `fl_new_hire (ult 7 dias)`,
    es.manager_name AS gestor,
    es.job_name AS cargo,
    es.job_family AS classe_cargo,
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
    LOWER(es.hrbp_work_email) AS hrbp,
    CASE
        WHEN es.is_manager IS TRUE THEN 1
        ELSE 0
    END AS fl_lider,
    LOWER(es.personal_email) AS email_pessoal,
    LOWER(es.employment_type) AS vinculo,
    LOWER(es.country) AS pais,
    LOWER(es.address_state) AS residencia_uf,
    LOWER(es.address_city) AS residencia_cidade,
    CAST(FROM_UTC_TIMESTAMP(es.ts_load, 'America/Sao_Paulo') AS DATE) AS dt_last_update,
    es.name_l1 AS l1_gestor,
    es.name_l2 AS l2_gestor,
    es.name_l3 AS l3_gestor,
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
ORDER BY
    es.dt_hired DESC
