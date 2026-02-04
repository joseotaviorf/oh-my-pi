WITH salary_bases_history AS (
    SELECT
        id_salary_basis,
        id_grade_rate,
        salary_basis_name,
        salary_basis_code AS salary_frequency,
        salary_basis_type,
        annualization_factor,
        is_active AS salary_basis_is_active,
        object_version_number,
        dt_available_from AS dt_effective_started,
        COALESCE(
            LEAD(dt_available_from) OVER (
                PARTITION BY id_salary_basis
                ORDER BY object_version_number
            ),
            DATE('4712-12-31')
        ) AS dt_effective_ended
    FROM
        datalake_pin_compensation_clean.salary_bases
    WHERE
        dt_available_from <= DATE('{load_end_date}')
),
valid_grades_deduped AS (
    SELECT
        id_job,
        id_grade,
        dt_effective_started,
        dt_effective_ended,
        object_version_number
    FROM
        datalake_pin_core_clean.valid_grades
    WHERE
        dt_effective_started <= DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY id_job
            ORDER BY dt_effective_started DESC, object_version_number DESC
        ) = 1
),
rates_deduped AS (
    SELECT
        id_rate,
        id_grade_ladder,
        currency_code,
        dt_effective_started,
        dt_effective_ended
    FROM
        datalake_pin_core_clean.rates
    WHERE
        dt_effective_started <= DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY id_grade_ladder, dt_effective_started
            ORDER BY dt_effective_started DESC, dt_effective_ended DESC
        ) = 1
),
rate_values_deduped AS (
    SELECT
        id_rate,
        id_rate_object,
        minimum_value,
        mid_value,
        maximum_value,
        dt_effective_started,
        dt_effective_ended
    FROM
        datalake_pin_core_clean.rate_values
    WHERE
        dt_effective_started <= DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY id_rate, id_rate_object, dt_effective_started
            ORDER BY dt_effective_started DESC, dt_effective_ended DESC
        ) = 1
),
salary_bases_deduped AS (
    SELECT
        id_salary_basis,
        id_grade_rate,
        salary_basis_name,
        salary_frequency,
        salary_basis_type,
        annualization_factor,
        dt_effective_started,
        dt_effective_ended
    FROM
        salary_bases_history
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY id_grade_rate, dt_effective_started
            ORDER BY dt_effective_started DESC, dt_effective_ended DESC
        ) = 1
),
dim_job_base AS (
SELECT
    -- Priority 0: SKs
    j.id_job AS sk_job,
    -- Priority 1: Non-SKs
    j.job_code,
    -- Priority 2: Non-metrics (properties)
    jt.name AS job_name,
    jft.job_family_name AS job_family,
    gt.name AS band,
    j.contribution_level AS career_track,
    si.set_name AS job_business_unit_group,
    glt.name AS salary_table,
    CASE
        WHEN glt.name = 'Deel' THEN 'United States'
        WHEN glt.name = 'Classifieds Geral' THEN 'Uruguay'
        WHEN RIGHT(glt.name, 2) = 'PT' OR glt.name LIKE '% PT' THEN 'Portugal'
        WHEN RIGHT(glt.name, 2) = 'MX' OR glt.name LIKE '% MX' THEN 'Mexico'
        WHEN RIGHT(glt.name, 3) = 'ARG' OR glt.name LIKE '% ARG' THEN 'Argentina'
        WHEN RIGHT(glt.name, 3) = 'PER' OR glt.name LIKE '% PER' THEN 'Peru'
        WHEN RIGHT(glt.name, 3) = 'ECU' OR glt.name LIKE '% ECU' THEN 'Ecuador'
        WHEN RIGHT(glt.name, 3) = 'PAN' OR glt.name LIKE '% PAN' THEN 'Panama'
        ELSE 'Brazil'
    END AS country,
    CASE
        WHEN glt.name IN ('Deel', 'Classifieds Geral')
            OR RIGHT(glt.name, 2) = 'PT' OR glt.name LIKE '% PT'
            OR RIGHT(glt.name, 2) = 'MX' OR glt.name LIKE '% MX'
            OR RIGHT(glt.name, 3) = 'ARG' OR glt.name LIKE '% ARG'
            OR RIGHT(glt.name, 3) = 'PER' OR glt.name LIKE '% PER'
            OR RIGHT(glt.name, 3) = 'ECU' OR glt.name LIKE '% ECU'
            OR RIGHT(glt.name, 3) = 'PAN' OR glt.name LIKE '% PAN'
            THEN CASE
                WHEN glt.name = 'Deel' THEN 'United States'
                WHEN glt.name = 'Classifieds Geral' THEN 'Uruguay'
                WHEN RIGHT(glt.name, 2) = 'PT' OR glt.name LIKE '% PT' THEN 'Portugal'
                WHEN RIGHT(glt.name, 2) = 'MX' OR glt.name LIKE '% MX' THEN 'Mexico'
                WHEN RIGHT(glt.name, 3) = 'ARG' OR glt.name LIKE '% ARG' THEN 'Argentina'
                WHEN RIGHT(glt.name, 3) = 'PER' OR glt.name LIKE '% PER' THEN 'Peru'
                WHEN RIGHT(glt.name, 3) = 'ECU' OR glt.name LIKE '% ECU' THEN 'Ecuador'
                WHEN RIGHT(glt.name, 3) = 'PAN' OR glt.name LIKE '% PAN' THEN 'Panama'
            END
        WHEN LEFT(COALESCE(gt_ptb.name, gt.name), 5) = 'Estag' THEN 'Estag'
        WHEN LEFT(COALESCE(gt_ptb.name, gt.name), 2) = 'JA' THEN 'JA'
        WHEN LEFT(glt.name, 8) = 'Ops Sale' THEN 'Ops Sale'
        WHEN SPLIT_PART(glt.name, ' ', 1) IN ('PM', 'DA', 'Eng', 'Prod', 'DSR', 'Growth')
            THEN SPLIT_PART(glt.name, ' ', 1)
        WHEN TRY_CAST(COALESCE(gt_ptb.name, gt.name) AS INT) >= 12 THEN 'EXEC'
        ELSE SPLIT_PART(glt.name, ' ', 1)
    END AS salary_table_group,
    sb.salary_basis_name,
    sb.salary_frequency,
    sb.salary_basis_type,
    jl.brazilian_occupation_code,
    j.work_arrangement AS working_hours_regime,
    j.weekly_hours AS workload,
    j.target_sop_currency AS currency_target_sop,
    r.currency_code AS currency_salary_range,
    -- Priority 3: Metrics
    sb.annualization_factor,
    j.target_plr,
    j.target_plr_salary_multiplier,
    j.target_rvv,
    j.target_sop,
    j.target_hiring_sop,
    j.target_bonus_tech_usd AS target_exceptional_bonus,
    CAST(rv.minimum_value AS DECIMAL(18, 2)) AS salary_range_min,
    CAST(rv.mid_value AS DECIMAL(18, 2)) AS salary_range_mid,
    CAST(rv.maximum_value AS DECIMAL(18, 2)) AS salary_range_max,
    j.is_time_clocking_required AS has_clock_in,
    j.is_active,
    (
        DATE('{load_end_date}') >= GREATEST(
            j.dt_effective_started,
            COALESCE(gl.dt_effective_started, j.dt_effective_started),
            COALESCE(glt.dt_effective_started, j.dt_effective_started),
            COALESCE(gt.dt_effective_started, j.dt_effective_started),
            COALESCE(gt_ptb.dt_effective_started, j.dt_effective_started),
            COALESCE(r.dt_effective_started, j.dt_effective_started),
            COALESCE(rv.dt_effective_started, j.dt_effective_started),
            COALESCE(sb.dt_effective_started, j.dt_effective_started)
        )
        AND DATE('{load_end_date}') < LEAST(
            j.dt_effective_ended,
            COALESCE(gl.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(glt.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(gt.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(gt_ptb.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(r.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(rv.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(sb.dt_effective_ended, DATE('4712-12-31'))
        )
    ) AS is_current,
    -- Priority 4: Date type
    GREATEST(
        j.dt_effective_started,
        COALESCE(gl.dt_effective_started, j.dt_effective_started),
        COALESCE(glt.dt_effective_started, j.dt_effective_started),
        COALESCE(gt.dt_effective_started, j.dt_effective_started),
        COALESCE(gt_ptb.dt_effective_started, j.dt_effective_started),
        COALESCE(r.dt_effective_started, j.dt_effective_started),
        COALESCE(rv.dt_effective_started, j.dt_effective_started),
        COALESCE(sb.dt_effective_started, j.dt_effective_started)
    ) AS dt_valid_from,
    NULLIF(
        LEAST(
            j.dt_effective_ended,
            COALESCE(gl.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(glt.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(gt.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(gt_ptb.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(r.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(rv.dt_effective_ended, DATE('4712-12-31')),
            COALESCE(sb.dt_effective_ended, DATE('4712-12-31'))
        ),
        DATE('4712-12-31')
    ) AS dt_valid_to,
    -- Priority 5: Timestamp type
    NOW() AS ts_load
FROM
    datalake_pin_core_clean.job AS j
LEFT JOIN
    datalake_pin_core_clean.job_translation AS jt
        ON jt.id_job = j.id_job
        AND jt.language = 'US'
        AND j.dt_effective_started < jt.dt_effective_ended
        AND j.dt_effective_ended > jt.dt_effective_started
LEFT JOIN
    datalake_pin_core_clean.job_family_translation AS jft
        ON jft.id_job_family = j.id_job_family
        AND j.dt_effective_started < jft.dt_effective_ended
        AND j.dt_effective_ended > jft.dt_effective_started
LEFT JOIN
    datalake_pin_core_clean.job_legislative AS jl
        ON jl.id_job = j.id_job
        AND j.dt_effective_started < jl.dt_effective_ended
        AND j.dt_effective_ended > jl.dt_effective_started
LEFT JOIN
    valid_grades_deduped AS vg
        ON vg.id_job = j.id_job
        AND j.dt_effective_started < vg.dt_effective_ended
        AND j.dt_effective_ended > vg.dt_effective_started
LEFT JOIN
    datalake_pin_core_clean.grade_translation AS gt
        ON gt.id_grade = vg.id_grade
        AND gt.language = 'US'
        AND j.dt_effective_started < gt.dt_effective_ended
        AND j.dt_effective_ended > gt.dt_effective_started
LEFT JOIN
    datalake_pin_core_clean.grade_translation AS gt_ptb
        ON gt_ptb.id_grade = vg.id_grade
        AND gt_ptb.language = 'PTB'
        AND j.dt_effective_started < gt_ptb.dt_effective_ended
        AND j.dt_effective_ended > gt_ptb.dt_effective_started
LEFT JOIN
    datalake_pin_core_clean.set_identifiers AS si
        ON si.id_set = j.id_set
LEFT JOIN
    datalake_pin_core_clean.grade_ladder AS gl
        ON gl.id_grade_ladder = j.id_grade_ladder
        AND j.dt_effective_started < gl.dt_effective_ended
        AND j.dt_effective_ended > gl.dt_effective_started
LEFT JOIN
    datalake_pin_core_clean.grade_ladder_translation AS glt
        ON glt.id_grade_ladder = j.id_grade_ladder
        AND glt.language = 'PTB'
        AND j.dt_effective_started < glt.dt_effective_ended
        AND j.dt_effective_ended > glt.dt_effective_started
LEFT JOIN
    rates_deduped AS r
        ON r.id_grade_ladder = j.id_grade_ladder
        AND j.dt_effective_started < r.dt_effective_ended
        AND j.dt_effective_ended > r.dt_effective_started
LEFT JOIN
    rate_values_deduped AS rv
        ON rv.id_rate = r.id_rate
        AND rv.id_rate_object = vg.id_grade
        AND j.dt_effective_started < rv.dt_effective_ended
        AND j.dt_effective_ended > rv.dt_effective_started
LEFT JOIN
    salary_bases_deduped AS sb
        ON sb.id_grade_rate = r.id_rate
        AND j.dt_effective_started < sb.dt_effective_ended
        AND j.dt_effective_ended > sb.dt_effective_started
WHERE
    j.dt_effective_started <= DATE('{load_end_date}')
    AND (
        gl.dt_effective_started IS NULL 
        OR gl.dt_effective_started <= DATE('{load_end_date}')
    )
    AND (
        glt.dt_effective_started IS NULL 
        OR glt.dt_effective_started <= DATE('{load_end_date}')
    )
    AND (
        gt.dt_effective_started IS NULL 
        OR gt.dt_effective_started <= DATE('{load_end_date}')
    )
    AND (
        gt_ptb.dt_effective_started IS NULL 
        OR gt_ptb.dt_effective_started <= DATE('{load_end_date}')
    )
    AND (
        r.dt_effective_started IS NULL 
        OR r.dt_effective_started <= DATE('{load_end_date}')
    )
    AND (
        rv.dt_effective_started IS NULL 
        OR rv.dt_effective_started <= DATE('{load_end_date}')
    )
    -- Ensure valid date overlap between all tables
    AND GREATEST(
        j.dt_effective_started,
        COALESCE(gl.dt_effective_started, j.dt_effective_started),
        COALESCE(glt.dt_effective_started, j.dt_effective_started),
        COALESCE(gt.dt_effective_started, j.dt_effective_started),
        COALESCE(gt_ptb.dt_effective_started, j.dt_effective_started),
        COALESCE(r.dt_effective_started, j.dt_effective_started),
        COALESCE(rv.dt_effective_started, j.dt_effective_started),
        COALESCE(sb.dt_effective_started, j.dt_effective_started)
    ) < LEAST(
        j.dt_effective_ended,
        COALESCE(gl.dt_effective_ended, DATE('4712-12-31')),
        COALESCE(glt.dt_effective_ended, DATE('4712-12-31')),
        COALESCE(gt.dt_effective_ended, DATE('4712-12-31')),
        COALESCE(gt_ptb.dt_effective_ended, DATE('4712-12-31')),
        COALESCE(r.dt_effective_ended, DATE('4712-12-31')),
        COALESCE(rv.dt_effective_ended, DATE('4712-12-31')),
        COALESCE(sb.dt_effective_ended, DATE('4712-12-31'))
    )
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY
            j.id_job,
            GREATEST(
                j.dt_effective_started,
                COALESCE(gl.dt_effective_started, j.dt_effective_started),
                COALESCE(glt.dt_effective_started, j.dt_effective_started),
                COALESCE(gt.dt_effective_started, j.dt_effective_started),
                COALESCE(gt_ptb.dt_effective_started, j.dt_effective_started),
                COALESCE(r.dt_effective_started, j.dt_effective_started),
                COALESCE(rv.dt_effective_started, j.dt_effective_started),
                COALESCE(sb.dt_effective_started, j.dt_effective_started)
            )
        ORDER BY
            COALESCE(r.dt_effective_started, DATE('1900-01-01')) DESC,
            COALESCE(rv.dt_effective_started, DATE('1900-01-01')) DESC,
            COALESCE(sb.dt_effective_started, DATE('1900-01-01')) DESC
    ) = 1
),
-- Create hash of dimension attributes to detect changes
dim_job_with_hash AS (
    SELECT
        *,
        MD5(CONCAT_WS('|',
            CAST(sk_job AS STRING),
            CAST(job_code AS STRING),
            CAST(job_name AS STRING),
            CAST(job_family AS STRING),
            CAST(band AS STRING),
            CAST(career_track AS STRING),
            CAST(job_business_unit_group AS STRING),
            CAST(salary_table AS STRING),
            CAST(country AS STRING),
            CAST(salary_table_group AS STRING),
            CAST(salary_basis_name AS STRING),
            CAST(salary_frequency AS STRING),
            CAST(salary_basis_type AS STRING),
            CAST(brazilian_occupation_code AS STRING),
            CAST(working_hours_regime AS STRING),
            CAST(workload AS STRING),
            CAST(currency_target_sop AS STRING),
            CAST(currency_salary_range AS STRING),
            CAST(has_clock_in AS STRING),
            CAST(is_active AS STRING)
        )) AS attributes_hash
    FROM
        dim_job_base
),
-- Group consecutive periods with identical attributes
dim_job_groups AS (
    SELECT
        *,
        SUM(CASE 
            WHEN LAG(attributes_hash) OVER (
                PARTITION BY sk_job
                ORDER BY dt_valid_from
            ) <> attributes_hash
                OR LAG(attributes_hash) OVER (
                    PARTITION BY sk_job
                    ORDER BY dt_valid_from
                ) IS NULL
            THEN 1
            ELSE 0
        END) OVER (
            PARTITION BY sk_job
            ORDER BY dt_valid_from
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS change_group
    FROM
        dim_job_with_hash
),
-- Consolidate consecutive periods with identical attributes into single SCD Type 2 versions
dim_job_consolidated AS (
    SELECT
        sk_job,
        job_code,
        job_name,
        job_family,
        band,
        career_track,
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
        is_active,
        change_group,
        MIN(dt_valid_from) AS dt_valid_from,
        MAX(COALESCE(dt_valid_to, DATE('4712-12-31'))) AS dt_valid_to
    FROM
        dim_job_groups
    GROUP BY
        sk_job,
        job_code,
        job_name,
        job_family,
        band,
        career_track,
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
        is_active,
        change_group
)
SELECT
    -- Priority 0: SKs
    sk_job,
    -- Priority 1: Non-SKs
    job_code,
    -- Priority 2: Non-metrics (properties)
    job_name,
    job_family,
    band,
    career_track,
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
    -- Priority 3: Metrics
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
    is_active,
    -- Recalculate is_current based on consolidated dates
    (
        DATE('{load_end_date}') >= dt_valid_from
        AND (
            dt_valid_to IS NULL
            OR dt_valid_to = DATE('4712-12-31')
            OR DATE('{load_end_date}') < dt_valid_to
        )
    ) AS is_current,
    -- Priority 4: Date type
    dt_valid_from,
    NULLIF(dt_valid_to, DATE('4712-12-31')) AS dt_valid_to,
    -- Priority 5: Timestamp type
    NOW() AS ts_load
FROM
    dim_job_consolidated
ORDER BY
    sk_job,
    dt_valid_from
