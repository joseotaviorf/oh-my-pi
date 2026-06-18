WITH
    active_headcount_per_job AS (
        SELECT
            snap.sk_job_version,
            COUNT(DISTINCT snap.sk_employee) AS active_headcount
        FROM
            dw_employee_details.fact_assignment_snapshots AS snap
        INNER JOIN
            dw_people.fact_employees AS emp
                ON snap.sk_employee = emp.sk_employee
                AND emp.is_current
                AND emp.is_active
        WHERE
            snap.is_current
            AND snap.is_primary_assignment_for_snapshot
            AND snap.sk_job_version <> '-1'
        GROUP BY
            snap.sk_job_version
    )
SELECT
    dj.job_name AS name,
    dj.job_code,
    dj.band AS banda,
    dj.job_family AS familia_cargo,
    org_job.career_track AS trilha,
    dj.salary_table AS tabela_salarial,
    dj.job_business_unit_group AS conjunto_cargos,
    CASE
        WHEN dj.country = 'Brazil' THEN 'Brasil'
        WHEN dj.country = 'United States' THEN 'Estados Unidos'
        WHEN dj.country = 'Uruguay' THEN 'Uruguai'
        ELSE dj.country
    END AS pais,
    CAST(dj.salary_range_min AS DECIMAL(10, 2)) AS p80,
    CAST(dj.salary_range_mid AS DECIMAL(10, 2)) AS p100,
    CAST(dj.salary_range_max AS DECIMAL(10, 2)) AS p120,
    CAST(dj.target_plr AS DECIMAL(10, 2)) AS rv_plr_target,
    CAST(dj.target_plr_salary_multiplier AS DECIMAL(10, 2)) AS rv_plr_salary_multiplier_target,
    CAST(dj.target_rvv AS DECIMAL(10, 2)) AS rvv_target,
    CAST(dj.target_sop AS DECIMAL(10, 2)) AS ilp_sop_target,
    CAST(dj.target_hiring_sop AS DECIMAL(10, 2)) AS ilp_sop_hiring_target,
    CAST(dj.target_exceptional_bonus AS DECIMAL(10, 2)) AS bonus_tech_usd_target,
    dj.brazilian_occupation_code AS cbo,
    CASE
        WHEN dj.is_active THEN 'Ativo'
        ELSE 'Inativo'
    END AS status,
    CASE
        WHEN dj.has_clock_in THEN 'Sim'
        ELSE 'Não'
    END AS marcaponto,
    dj.working_hours_regime AS regime_jornada_empregado,
    dj.workload AS turnotrabalho,
    dj.dt_valid_from AS last_update_date,
    COALESCE(ah.active_headcount, 0) AS active_headcount,
    (CAST(dj.target_plr AS DECIMAL(10, 2)) IS DISTINCT FROM st.target_plr) AS is_rv_plr_exception,
    (
        CAST(dj.target_plr_salary_multiplier AS DECIMAL(10, 2))
        IS DISTINCT FROM st.target_plr_salary_multiplier
    ) AS is_rv_plr_salary_multiplier_exception,
    (CAST(dj.target_rvv AS DECIMAL(10, 2)) IS DISTINCT FROM st.target_rvv) AS is_rvv_exception,
    (CAST(dj.target_sop AS DECIMAL(10, 2)) IS DISTINCT FROM st.target_sop) AS is_ilp_sop_exception,
    (
        CAST(dj.target_hiring_sop AS DECIMAL(10, 2))
        IS DISTINCT FROM st.target_hiring_sop
    ) AS is_ilp_sop_hiring_exception,
    (
        (CAST(dj.target_plr AS DECIMAL(10, 2)) IS DISTINCT FROM st.target_plr)
        OR (
            CAST(dj.target_plr_salary_multiplier AS DECIMAL(10, 2))
            IS DISTINCT FROM st.target_plr_salary_multiplier
        )
        OR (CAST(dj.target_rvv AS DECIMAL(10, 2)) IS DISTINCT FROM st.target_rvv)
        OR (CAST(dj.target_sop AS DECIMAL(10, 2)) IS DISTINCT FROM st.target_sop)
        OR (
            CAST(dj.target_hiring_sop AS DECIMAL(10, 2))
            IS DISTINCT FROM st.target_hiring_sop
        )
    ) AS is_any_exception,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    dw_compensation.dim_job AS dj
LEFT JOIN
    active_headcount_per_job AS ah
        ON dj.sk_job_version = ah.sk_job_version
LEFT JOIN
    dw_organization.dim_job AS org_job
        ON dj.id_job = org_job.sk_job
LEFT JOIN
    dw_compensation.fact_salary_table_targets AS st
        ON dj.salary_table = st.salary_table
        AND dj.band = st.band
        AND st.is_current
WHERE
    dj.is_active
    AND dj.is_current
    AND (dj.job_name IS NOT NULL OR dj.job_code IS NOT NULL)
ORDER BY
    dj.is_active DESC,
    pais,
    dj.job_business_unit_group,
    dj.salary_table,
    TRY_CAST(dj.band AS INT) DESC,
    dj.job_name
