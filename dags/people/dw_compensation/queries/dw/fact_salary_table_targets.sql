WITH date_range AS (
    SELECT
        date AS dt_reference
    FROM
        dw_public.dim_date
    WHERE
        date >= DATE_ADD(CURRENT_DATE, -730)
        AND date <= CURRENT_DATE
),
active_assignments AS (
    SELECT
        dt_ref.dt_reference,
        assign.id_job,
        assign.id_person
    FROM
        date_range AS dt_ref
    CROSS JOIN
        datalake_pin_core_clean.all_assignments AS assign
    WHERE
        assign.assignment_status_type = 'ACTIVE'
        AND assign.assignment_type IN ('E', 'C')
        AND assign.dt_effective_started <= dt_ref.dt_reference
        AND assign.dt_effective_ended >= dt_ref.dt_reference
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY dt_ref.dt_reference, assign.id_person
            ORDER BY assign.dt_effective_started DESC
        ) = 1
),
active_headcount_per_job AS (
    SELECT
        dt_reference,
        id_job,
        COUNT(DISTINCT id_person) AS active_headcount
    FROM
        active_assignments
    GROUP BY
        dt_reference,
        id_job
),
dim_job_at_date AS (
    SELECT
        dt_ref.dt_reference,
        dim_job.id_job,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_plr,
        dim_job.target_plr_salary_multiplier,
        dim_job.target_rvv,
        dim_job.target_sop,
        dim_job.target_hiring_sop,
        dim_job.target_exceptional_bonus
    FROM
        date_range AS dt_ref
    CROSS JOIN
        dw_compensation.dim_job AS dim_job
    WHERE
        dim_job.dt_valid_from <= dt_ref.dt_reference
        AND dim_job.dt_valid_to > dt_ref.dt_reference
        AND dim_job.salary_table IS NOT NULL
        AND dim_job.band IS NOT NULL
        AND dim_job.is_active = TRUE
),
base_groups AS (
    SELECT DISTINCT
        dt_reference,
        salary_table,
        band
    FROM
        dim_job_at_date
),
frequencies_plr AS (
    SELECT
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_plr,
        SUM(COALESCE(headcount.active_headcount, 0)) AS headcount_frequency,
        COUNT(dim_job.id_job) AS job_frequency
    FROM
        dim_job_at_date AS dim_job
    LEFT JOIN
        active_headcount_per_job AS headcount
            ON dim_job.id_job = headcount.id_job
            AND dim_job.dt_reference = headcount.dt_reference
    WHERE
        dim_job.target_plr IS NOT NULL
    GROUP BY
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_plr
),
most_frequent_plr AS (
    SELECT
        dt_reference,
        salary_table,
        band,
        target_plr,
        headcount_frequency,
        job_frequency,
        SUM(headcount_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_headcount,
        SUM(job_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_jobs
    FROM
        frequencies_plr
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY dt_reference, salary_table, band
            ORDER BY headcount_frequency DESC, job_frequency DESC
        ) = 1
),
frequencies_plr_multiplier AS (
    SELECT
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_plr_salary_multiplier,
        SUM(COALESCE(headcount.active_headcount, 0)) AS headcount_frequency,
        COUNT(dim_job.id_job) AS job_frequency
    FROM
        dim_job_at_date AS dim_job
    LEFT JOIN
        active_headcount_per_job AS headcount
            ON dim_job.id_job = headcount.id_job
            AND dim_job.dt_reference = headcount.dt_reference
    WHERE
        dim_job.target_plr_salary_multiplier IS NOT NULL
    GROUP BY
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_plr_salary_multiplier
),
most_frequent_plr_multiplier AS (
    SELECT
        dt_reference,
        salary_table,
        band,
        target_plr_salary_multiplier,
        headcount_frequency,
        job_frequency,
        SUM(headcount_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_headcount,
        SUM(job_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_jobs
    FROM
        frequencies_plr_multiplier
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY dt_reference, salary_table, band
            ORDER BY headcount_frequency DESC, job_frequency DESC
        ) = 1
),
frequencies_rvv AS (
    SELECT
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_rvv,
        SUM(COALESCE(headcount.active_headcount, 0)) AS headcount_frequency,
        COUNT(dim_job.id_job) AS job_frequency
    FROM
        dim_job_at_date AS dim_job
    LEFT JOIN
        active_headcount_per_job AS headcount
            ON dim_job.id_job = headcount.id_job
            AND dim_job.dt_reference = headcount.dt_reference
    WHERE
        dim_job.target_rvv IS NOT NULL
    GROUP BY
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_rvv
),
most_frequent_rvv AS (
    SELECT
        dt_reference,
        salary_table,
        band,
        target_rvv,
        headcount_frequency,
        job_frequency,
        SUM(headcount_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_headcount,
        SUM(job_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_jobs
    FROM
        frequencies_rvv
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY dt_reference, salary_table, band
            ORDER BY headcount_frequency DESC, job_frequency DESC
        ) = 1
),
frequencies_sop AS (
    SELECT
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_sop,
        SUM(COALESCE(headcount.active_headcount, 0)) AS headcount_frequency,
        COUNT(dim_job.id_job) AS job_frequency
    FROM
        dim_job_at_date AS dim_job
    LEFT JOIN
        active_headcount_per_job AS headcount
            ON dim_job.id_job = headcount.id_job
            AND dim_job.dt_reference = headcount.dt_reference
    WHERE
        dim_job.target_sop IS NOT NULL
    GROUP BY
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_sop
),
most_frequent_sop AS (
    SELECT
        dt_reference,
        salary_table,
        band,
        target_sop,
        headcount_frequency,
        job_frequency,
        SUM(headcount_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_headcount,
        SUM(job_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_jobs
    FROM
        frequencies_sop
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY dt_reference, salary_table, band
            ORDER BY headcount_frequency DESC, job_frequency DESC
        ) = 1
),
frequencies_hiring_sop AS (
    SELECT
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_hiring_sop,
        SUM(COALESCE(headcount.active_headcount, 0)) AS headcount_frequency,
        COUNT(dim_job.id_job) AS job_frequency
    FROM
        dim_job_at_date AS dim_job
    LEFT JOIN
        active_headcount_per_job AS headcount
            ON dim_job.id_job = headcount.id_job
            AND dim_job.dt_reference = headcount.dt_reference
    WHERE
        dim_job.target_hiring_sop IS NOT NULL
    GROUP BY
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_hiring_sop
),
most_frequent_hiring_sop AS (
    SELECT
        dt_reference,
        salary_table,
        band,
        target_hiring_sop,
        headcount_frequency,
        job_frequency,
        SUM(headcount_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_headcount,
        SUM(job_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_jobs
    FROM
        frequencies_hiring_sop
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY dt_reference, salary_table, band
            ORDER BY headcount_frequency DESC, job_frequency DESC
        ) = 1
),
frequencies_exceptional_bonus AS (
    SELECT
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_exceptional_bonus,
        SUM(COALESCE(headcount.active_headcount, 0)) AS headcount_frequency,
        COUNT(dim_job.id_job) AS job_frequency
    FROM
        dim_job_at_date AS dim_job
    LEFT JOIN
        active_headcount_per_job AS headcount
            ON dim_job.id_job = headcount.id_job
            AND dim_job.dt_reference = headcount.dt_reference
    WHERE
        dim_job.target_exceptional_bonus IS NOT NULL
    GROUP BY
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        dim_job.target_exceptional_bonus
),
most_frequent_exceptional_bonus AS (
    SELECT
        dt_reference,
        salary_table,
        band,
        target_exceptional_bonus,
        headcount_frequency,
        job_frequency,
        SUM(headcount_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_headcount,
        SUM(job_frequency) OVER (PARTITION BY dt_reference, salary_table, band) AS total_jobs
    FROM
        frequencies_exceptional_bonus
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY dt_reference, salary_table, band
            ORDER BY headcount_frequency DESC, job_frequency DESC
        ) = 1
),
totals AS (
    SELECT
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band,
        SUM(COALESCE(headcount.active_headcount, 0)) AS total_active_headcount,
        COUNT(DISTINCT dim_job.id_job) AS total_active_jobs
    FROM
        dim_job_at_date AS dim_job
    LEFT JOIN
        active_headcount_per_job AS headcount
            ON dim_job.id_job = headcount.id_job
            AND dim_job.dt_reference = headcount.dt_reference
    GROUP BY
        dim_job.dt_reference,
        dim_job.salary_table,
        dim_job.band
)
SELECT
    -- Priority 0: SKs
    MD5(CONCAT_WS('|',
        base.salary_table,
        base.band,
        base.dt_reference
    )) AS sk_salary_table_targets,
    -- Priority 1: Non-SKs
    base.salary_table,
    base.band,
    -- Priority 2: Non-metrics (properties)
    CAST(freq_plr.target_plr AS DECIMAL(18, 2)) AS target_plr,
    CAST(freq_plr_mult.target_plr_salary_multiplier AS DECIMAL(18, 2)) AS target_plr_salary_multiplier,
    CAST(freq_rvv.target_rvv AS DECIMAL(18, 2)) AS target_rvv,
    CAST(freq_sop.target_sop AS DECIMAL(18, 2)) AS target_sop,
    CAST(freq_hiring_sop.target_hiring_sop AS DECIMAL(18, 2)) AS target_hiring_sop,
    CAST(freq_bonus.target_exceptional_bonus AS DECIMAL(18, 2)) AS target_exceptional_bonus,
    -- Priority 3: Metrics
    CAST(job_totals.total_active_headcount AS INT) AS total_active_headcount,
    CAST(job_totals.total_active_jobs AS INT) AS total_active_jobs,
    (
        COALESCE(freq_plr.headcount_frequency, 0) < COALESCE(freq_plr.total_headcount, 0)
        OR COALESCE(freq_plr_mult.headcount_frequency, 0) < COALESCE(freq_plr_mult.total_headcount, 0)
        OR COALESCE(freq_rvv.headcount_frequency, 0) < COALESCE(freq_rvv.total_headcount, 0)
        OR COALESCE(freq_sop.headcount_frequency, 0) < COALESCE(freq_sop.total_headcount, 0)
        OR COALESCE(freq_hiring_sop.headcount_frequency, 0) < COALESCE(freq_hiring_sop.total_headcount, 0)
    ) AS has_headcount_exceptions,
    (
        COALESCE(freq_plr.job_frequency, 0) < COALESCE(freq_plr.total_jobs, 0)
        OR COALESCE(freq_plr_mult.job_frequency, 0) < COALESCE(freq_plr_mult.total_jobs, 0)
        OR COALESCE(freq_rvv.job_frequency, 0) < COALESCE(freq_rvv.total_jobs, 0)
        OR COALESCE(freq_sop.job_frequency, 0) < COALESCE(freq_sop.total_jobs, 0)
        OR COALESCE(freq_hiring_sop.job_frequency, 0) < COALESCE(freq_hiring_sop.total_jobs, 0)
    ) AS has_job_exceptions,
    -- Priority 4: Boolean type
    CASE
        WHEN base.dt_reference = CURRENT_DATE THEN TRUE
        ELSE FALSE
    END AS is_current,
    -- Priority 5: Date type
    base.dt_reference,
    -- Priority 6: Timestamp type
    NOW() AS ts_load
FROM
    base_groups AS base
LEFT JOIN
    most_frequent_plr AS freq_plr
        ON base.salary_table = freq_plr.salary_table
        AND base.band = freq_plr.band
        AND base.dt_reference = freq_plr.dt_reference
LEFT JOIN
    most_frequent_plr_multiplier AS freq_plr_mult
        ON base.salary_table = freq_plr_mult.salary_table
        AND base.band = freq_plr_mult.band
        AND base.dt_reference = freq_plr_mult.dt_reference
LEFT JOIN
    most_frequent_rvv AS freq_rvv
        ON base.salary_table = freq_rvv.salary_table
        AND base.band = freq_rvv.band
        AND base.dt_reference = freq_rvv.dt_reference
LEFT JOIN
    most_frequent_sop AS freq_sop
        ON base.salary_table = freq_sop.salary_table
        AND base.band = freq_sop.band
        AND base.dt_reference = freq_sop.dt_reference
LEFT JOIN
    most_frequent_hiring_sop AS freq_hiring_sop
        ON base.salary_table = freq_hiring_sop.salary_table
        AND base.band = freq_hiring_sop.band
        AND base.dt_reference = freq_hiring_sop.dt_reference
LEFT JOIN
    most_frequent_exceptional_bonus AS freq_bonus
        ON base.salary_table = freq_bonus.salary_table
        AND base.band = freq_bonus.band
        AND base.dt_reference = freq_bonus.dt_reference
LEFT JOIN
    totals AS job_totals
        ON base.salary_table = job_totals.salary_table
        AND base.band = job_totals.band
        AND base.dt_reference = job_totals.dt_reference
