SELECT
    st.salary_table,
    st.band,
    dj.country,
    dj.salary_table_group,
    CAST(dj.salary_range_min AS DECIMAL(10, 2)) AS p80,
    CAST(dj.salary_range_mid AS DECIMAL(10, 2)) AS p100,
    CAST(dj.salary_range_max AS DECIMAL(10, 2)) AS p120,
    st.target_plr AS rv_plr_target,
    st.target_plr_salary_multiplier AS rv_plr_salary_multiplier_target,
    st.target_rvv AS rvv_target,
    st.target_sop AS ilp_sop_target,
    st.target_hiring_sop AS ilp_sop_hiring_target,
    st.total_active_headcount,
    st.total_active_jobs,
    st.has_headcount_exceptions,
    st.has_job_exceptions,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    dw_compensation.fact_salary_table_targets AS st
LEFT JOIN
    dw_compensation.dim_job AS dj
        ON st.salary_table = dj.salary_table
        AND st.band = dj.band
        AND dj.is_active
        AND dj.is_current
WHERE
    st.is_current
    AND st.salary_table IS NOT NULL
    AND st.band IS NOT NULL
ORDER BY
    dj.country,
    dj.salary_table_group,
    st.salary_table,
    TRY_CAST(st.band AS INT) DESC
