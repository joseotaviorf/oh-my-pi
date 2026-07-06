-- Non-compensation job dimension so dw_employee_details consumers (without dw_compensation
-- access) can time-travel job attributes via fact_assignment_snapshots.sk_job_version.
-- sk_job_version intentionally reuses the same hash/grain as dw_compensation.dim_job
-- (MD5 of id_job + dt_valid_from over datalake_people.job_with_salary_table) so both
-- dimensions share one version key. That grain is driven upstream by both job and
-- compensation attribute changes, so two consecutive versions here can carry identical
-- band/job_name/job_family when only a (deliberately excluded) compensation attribute
-- changed. This is a known trade-off of preserving join compatibility with the fact.
SELECT
    MD5(
        CONCAT_WS(
            '|',
            CAST(id_job AS STRING),
            CAST(dt_valid_from AS STRING)
        )
    ) AS sk_job_version,
    id_job,
    job_code,
    job_name,
    job_family,
    CASE
        WHEN job_family = 'Jovem Aprendiz' THEN 'young apprentice'
        WHEN job_family = 'Estagiario' THEN 'intern'
        WHEN job_family IS NOT NULL THEN 'clt'
    END AS employment_type,
    band,
    job_business_unit_group,
    brazilian_occupation_code,
    working_hours_regime,
    workload,
    has_clock_in,
    is_leadership_job,
    is_active,
    is_current,
    dt_valid_from,
    COALESCE(dt_valid_to, DATE('9999-12-31')) AS dt_valid_to,
    NOW() AS ts_load
FROM
    datalake_people.job_with_salary_table
WHERE
    dt_valid_from <= DATE('{load_start_date}')
ORDER BY
    sk_job_version
