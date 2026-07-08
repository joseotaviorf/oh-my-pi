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
            snap.is_current_for_employee
            AND snap.sk_job_version <> '-1'
        GROUP BY
            snap.sk_job_version
    ),
    frequencies_min_salary AS (
        SELECT
            dj.salary_table,
            dj.band,
            dj.salary_range_min,
            SUM(COALESCE(ah.active_headcount, 0)) AS headcount_frequency,
            COUNT(dj.id_job) AS job_frequency
        FROM
            dw_compensation.dim_job AS dj
        LEFT JOIN
            active_headcount_per_job AS ah
                ON dj.sk_job_version = ah.sk_job_version
        WHERE
            dj.salary_range_min IS NOT NULL
            AND dj.is_active
            AND dj.is_current
        GROUP BY
            dj.salary_table,
            dj.band,
            dj.salary_range_min
    ),
    ranked_min_salary AS (
        SELECT
            salary_table,
            band,
            salary_range_min,
            ROW_NUMBER() OVER (
                PARTITION BY salary_table, band
                ORDER BY headcount_frequency DESC, job_frequency DESC
            ) AS rn
        FROM
            frequencies_min_salary
    ),
    frequencies_mid_salary AS (
        SELECT
            dj.salary_table,
            dj.band,
            dj.salary_range_mid,
            SUM(COALESCE(ah.active_headcount, 0)) AS headcount_frequency,
            COUNT(dj.id_job) AS job_frequency
        FROM
            dw_compensation.dim_job AS dj
        LEFT JOIN
            active_headcount_per_job AS ah
                ON dj.sk_job_version = ah.sk_job_version
        WHERE
            dj.salary_range_mid IS NOT NULL
            AND dj.is_active
            AND dj.is_current
        GROUP BY
            dj.salary_table,
            dj.band,
            dj.salary_range_mid
    ),
    ranked_mid_salary AS (
        SELECT
            salary_table,
            band,
            salary_range_mid,
            ROW_NUMBER() OVER (
                PARTITION BY salary_table, band
                ORDER BY headcount_frequency DESC, job_frequency DESC
            ) AS rn
        FROM
            frequencies_mid_salary
    ),
    frequencies_max_salary AS (
        SELECT
            dj.salary_table,
            dj.band,
            dj.salary_range_max,
            SUM(COALESCE(ah.active_headcount, 0)) AS headcount_frequency,
            COUNT(dj.id_job) AS job_frequency
        FROM
            dw_compensation.dim_job AS dj
        LEFT JOIN
            active_headcount_per_job AS ah
                ON dj.sk_job_version = ah.sk_job_version
        WHERE
            dj.salary_range_max IS NOT NULL
            AND dj.is_active
            AND dj.is_current
        GROUP BY
            dj.salary_table,
            dj.band,
            dj.salary_range_max
    ),
    ranked_max_salary AS (
        SELECT
            salary_table,
            band,
            salary_range_max,
            ROW_NUMBER() OVER (
                PARTITION BY salary_table, band
                ORDER BY headcount_frequency DESC, job_frequency DESC
            ) AS rn
        FROM
            frequencies_max_salary
    ),
    frequencies_plr AS (
        SELECT
            dj.salary_table,
            dj.band,
            dj.target_plr,
            SUM(COALESCE(ah.active_headcount, 0)) AS headcount_frequency,
            COUNT(dj.id_job) AS job_frequency
        FROM
            dw_compensation.dim_job AS dj
        LEFT JOIN
            active_headcount_per_job AS ah
                ON dj.sk_job_version = ah.sk_job_version
        WHERE
            dj.target_plr IS NOT NULL
            AND dj.is_active
            AND dj.is_current
        GROUP BY
            dj.salary_table,
            dj.band,
            dj.target_plr
    ),
    plr_target_frequencies AS (
        SELECT
            salary_table,
            band,
            target_plr,
            headcount_frequency,
            job_frequency,
            SUM(headcount_frequency) OVER (
                PARTITION BY salary_table, band
            ) AS total_headcount_in_group,
            SUM(job_frequency) OVER (
                PARTITION BY salary_table, band
            ) AS total_jobs_in_group
        FROM
            frequencies_plr
    ),
    frequencies_plr_multiplier AS (
        SELECT
            dj.salary_table,
            dj.band,
            dj.target_plr_salary_multiplier,
            SUM(COALESCE(ah.active_headcount, 0)) AS headcount_frequency,
            COUNT(dj.id_job) AS job_frequency
        FROM
            dw_compensation.dim_job AS dj
        LEFT JOIN
            active_headcount_per_job AS ah
                ON dj.sk_job_version = ah.sk_job_version
        WHERE
            dj.target_plr_salary_multiplier IS NOT NULL
            AND dj.is_active
            AND dj.is_current
        GROUP BY
            dj.salary_table,
            dj.band,
            dj.target_plr_salary_multiplier
    ),
    plr_multiplier_target_frequencies AS (
        SELECT
            salary_table,
            band,
            target_plr_salary_multiplier,
            headcount_frequency,
            job_frequency,
            SUM(headcount_frequency) OVER (
                PARTITION BY salary_table, band
            ) AS total_headcount_in_group,
            SUM(job_frequency) OVER (
                PARTITION BY salary_table, band
            ) AS total_jobs_in_group
        FROM
            frequencies_plr_multiplier
    ),
    frequencies_rvv AS (
        SELECT
            dj.salary_table,
            dj.band,
            dj.target_rvv,
            SUM(COALESCE(ah.active_headcount, 0)) AS headcount_frequency,
            COUNT(dj.id_job) AS job_frequency
        FROM
            dw_compensation.dim_job AS dj
        LEFT JOIN
            active_headcount_per_job AS ah
                ON dj.sk_job_version = ah.sk_job_version
        WHERE
            dj.target_rvv IS NOT NULL
            AND dj.is_active
            AND dj.is_current
        GROUP BY
            dj.salary_table,
            dj.band,
            dj.target_rvv
    ),
    rvv_target_frequencies AS (
        SELECT
            salary_table,
            band,
            target_rvv,
            headcount_frequency,
            job_frequency,
            SUM(headcount_frequency) OVER (
                PARTITION BY salary_table, band
            ) AS total_headcount_in_group,
            SUM(job_frequency) OVER (
                PARTITION BY salary_table, band
            ) AS total_jobs_in_group
        FROM
            frequencies_rvv
    ),
    frequencies_sop AS (
        SELECT
            dj.salary_table,
            dj.band,
            dj.target_sop,
            SUM(COALESCE(ah.active_headcount, 0)) AS headcount_frequency,
            COUNT(dj.id_job) AS job_frequency
        FROM
            dw_compensation.dim_job AS dj
        LEFT JOIN
            active_headcount_per_job AS ah
                ON dj.sk_job_version = ah.sk_job_version
        WHERE
            dj.target_sop IS NOT NULL
            AND dj.is_active
            AND dj.is_current
        GROUP BY
            dj.salary_table,
            dj.band,
            dj.target_sop
    ),
    sop_target_frequencies AS (
        SELECT
            salary_table,
            band,
            target_sop,
            headcount_frequency,
            job_frequency,
            SUM(headcount_frequency) OVER (
                PARTITION BY salary_table, band
            ) AS total_headcount_in_group,
            SUM(job_frequency) OVER (
                PARTITION BY salary_table, band
            ) AS total_jobs_in_group
        FROM
            frequencies_sop
    ),
    frequencies_hiring_sop AS (
        SELECT
            dj.salary_table,
            dj.band,
            dj.target_hiring_sop,
            SUM(COALESCE(ah.active_headcount, 0)) AS headcount_frequency,
            COUNT(dj.id_job) AS job_frequency
        FROM
            dw_compensation.dim_job AS dj
        LEFT JOIN
            active_headcount_per_job AS ah
                ON dj.sk_job_version = ah.sk_job_version
        WHERE
            dj.target_hiring_sop IS NOT NULL
            AND dj.is_active
            AND dj.is_current
        GROUP BY
            dj.salary_table,
            dj.band,
            dj.target_hiring_sop
    ),
    hiring_sop_target_frequencies AS (
        SELECT
            salary_table,
            band,
            target_hiring_sop,
            headcount_frequency,
            job_frequency,
            SUM(headcount_frequency) OVER (
                PARTITION BY salary_table, band
            ) AS total_headcount_in_group,
            SUM(job_frequency) OVER (
                PARTITION BY salary_table, band
            ) AS total_jobs_in_group
        FROM
            frequencies_hiring_sop
    ),
    dim_job_by_group AS (
        SELECT
            dj.salary_table,
            dj.band,
            MAX(
                CASE
                    WHEN dj.country = 'Brazil' THEN 'Brasil'
                    WHEN dj.country = 'United States' THEN 'Estados Unidos'
                    WHEN dj.country = 'Uruguay' THEN 'Uruguai'
                    ELSE dj.country
                END
            ) AS country,
            MAX(dj.salary_table_group) AS salary_table_group
        FROM
            dw_compensation.dim_job AS dj
        WHERE
            dj.is_active
            AND dj.is_current
            AND dj.salary_table IS NOT NULL
            AND dj.band IS NOT NULL
        GROUP BY
            dj.salary_table,
            dj.band
    )
SELECT
    st.salary_table,
    st.band,
    dj_grp.country,
    dj_grp.salary_table_group,
    CAST(min_s.salary_range_min AS DECIMAL(10, 2)) AS p80,
    CAST(mid_s.salary_range_mid AS DECIMAL(10, 2)) AS p100,
    CAST(max_s.salary_range_max AS DECIMAL(10, 2)) AS p120,
    CAST(st.target_plr AS DECIMAL(10, 2)) AS rv_plr_target,
    CAST(st.target_plr_salary_multiplier AS DECIMAL(10, 2)) AS rv_plr_salary_multiplier_target,
    CAST(st.target_rvv AS DECIMAL(10, 2)) AS rvv_target,
    CAST(st.target_sop AS DECIMAL(10, 2)) AS ilp_sop_target,
    CAST(st.target_hiring_sop AS DECIMAL(10, 2)) AS ilp_sop_hiring_target,
    CONCAT(
        '[HC: ',
        plr.headcount_frequency,
        ' / ',
        plr.total_headcount_in_group,
        '] | [Job: ',
        plr.job_frequency,
        ' / ',
        plr.total_jobs_in_group,
        ']'
    ) AS rv_plr_ratio,
    CONCAT(
        '[HC: ',
        plr_m.headcount_frequency,
        ' / ',
        plr_m.total_headcount_in_group,
        '] | [Job: ',
        plr_m.job_frequency,
        ' / ',
        plr_m.total_jobs_in_group,
        ']'
    ) AS rv_plr_salary_multiplier_ratio,
    CONCAT(
        '[HC: ',
        rvv.headcount_frequency,
        ' / ',
        rvv.total_headcount_in_group,
        '] | [Job: ',
        rvv.job_frequency,
        ' / ',
        rvv.total_jobs_in_group,
        ']'
    ) AS rvv_ratio,
    CONCAT(
        '[HC: ',
        sop.headcount_frequency,
        ' / ',
        sop.total_headcount_in_group,
        '] | [Job: ',
        sop.job_frequency,
        ' / ',
        sop.total_jobs_in_group,
        ']'
    ) AS ilp_sop_ratio,
    CONCAT(
        '[HC: ',
        h_sop.headcount_frequency,
        ' / ',
        h_sop.total_headcount_in_group,
        '] | [Job: ',
        h_sop.job_frequency,
        ' / ',
        h_sop.total_jobs_in_group,
        ']'
    ) AS ilp_sop_hiring_ratio,
    st.has_headcount_exceptions,
    st.has_job_exceptions,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    dw_compensation.fact_salary_table_targets AS st
INNER JOIN
    dim_job_by_group AS dj_grp
        ON st.salary_table = dj_grp.salary_table
        AND st.band = dj_grp.band
LEFT JOIN
    ranked_min_salary AS min_s
        ON st.salary_table = min_s.salary_table
        AND st.band = min_s.band
        AND min_s.rn = 1
LEFT JOIN
    ranked_mid_salary AS mid_s
        ON st.salary_table = mid_s.salary_table
        AND st.band = mid_s.band
        AND mid_s.rn = 1
LEFT JOIN
    ranked_max_salary AS max_s
        ON st.salary_table = max_s.salary_table
        AND st.band = max_s.band
        AND max_s.rn = 1
LEFT JOIN
    plr_target_frequencies AS plr
        ON st.salary_table = plr.salary_table
        AND st.band = plr.band
        AND CAST(st.target_plr AS DECIMAL(10, 2)) = CAST(plr.target_plr AS DECIMAL(10, 2))
LEFT JOIN
    plr_multiplier_target_frequencies AS plr_m
        ON st.salary_table = plr_m.salary_table
        AND st.band = plr_m.band
        AND CAST(st.target_plr_salary_multiplier AS DECIMAL(10, 2))
            = CAST(plr_m.target_plr_salary_multiplier AS DECIMAL(10, 2))
LEFT JOIN
    rvv_target_frequencies AS rvv
        ON st.salary_table = rvv.salary_table
        AND st.band = rvv.band
        AND CAST(st.target_rvv AS DECIMAL(10, 2)) = CAST(rvv.target_rvv AS DECIMAL(10, 2))
LEFT JOIN
    sop_target_frequencies AS sop
        ON st.salary_table = sop.salary_table
        AND st.band = sop.band
        AND CAST(st.target_sop AS DECIMAL(10, 2)) = CAST(sop.target_sop AS DECIMAL(10, 2))
LEFT JOIN
    hiring_sop_target_frequencies AS h_sop
        ON st.salary_table = h_sop.salary_table
        AND st.band = h_sop.band
        AND CAST(st.target_hiring_sop AS DECIMAL(10, 2))
            = CAST(h_sop.target_hiring_sop AS DECIMAL(10, 2))
WHERE
    st.is_current
    AND st.salary_table IS NOT NULL
    AND st.band IS NOT NULL
ORDER BY
    dj_grp.country,
    dj_grp.salary_table_group,
    st.salary_table,
    TRY_CAST(st.band AS INT) DESC
