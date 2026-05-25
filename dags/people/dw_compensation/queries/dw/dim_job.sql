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
    salary_table,
    country,
    salary_table_group,
    salary_basis_name,
    salary_frequency,
    salary_basis_type,
    brazilian_occupation_code,
    working_hours_regime,
    workload,
    currency_target_sop,
    currency_salary_range,
    annualization_factor,
    target_plr,
    target_plr_salary_multiplier,
    target_rvv,
    target_sop,
    target_hiring_sop,
    target_exceptional_bonus,
    salary_range_min,
    salary_range_mid,
    salary_range_max,
    has_clock_in,
    is_leadership_job,
    is_active,
    is_current,
    dt_valid_from,
    COALESCE(
        NULLIF(dt_valid_to, DATE('4712-12-31')),
        DATE('9999-12-31')
    ) AS dt_valid_to,
    NOW() AS ts_load
FROM
    datalake_people.job_with_salary_table
WHERE
    dt_valid_from <= CURRENT_DATE
ORDER BY
    sk_job_version
