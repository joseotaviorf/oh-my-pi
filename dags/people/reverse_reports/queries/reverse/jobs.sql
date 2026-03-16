SELECT
    dj.job_name AS name,
    dj.job_code,
    dj.band,
    dj.job_family AS job_family,
    dj.salary_table_group AS career_track,
    dj.salary_table AS salary_table,
    dj.job_business_unit_group AS job_business_unit_group,
    dj.country,
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
        WHEN dj.is_active THEN 'Active'
        ELSE 'Inactive'
    END AS status,
    CASE
        WHEN dj.has_clock_in THEN 'Yes'
        ELSE 'No'
    END AS has_clock_in,
    dj.working_hours_regime,
    dj.workload,
    dj.dt_valid_from AS last_update_date,
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
    dw_compensation.fact_salary_table_targets AS st
        ON dj.salary_table = st.salary_table
        AND dj.band = st.band
        AND st.is_current
WHERE
    dj.is_active
    AND (dj.job_name IS NOT NULL OR dj.job_code IS NOT NULL)
ORDER BY
    dj.is_active DESC,
    dj.country,
    dj.job_business_unit_group,
    dj.salary_table,
    TRY_CAST(dj.band AS INT) DESC,
    dj.job_name
