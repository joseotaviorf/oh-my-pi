WITH
job_ranked AS (
    SELECT
        id_job,
        job_code,
        id_job_family,
        contribution_level,
        id_grade_ladder,
        id_set,
        work_arrangement,
        target_sop_currency,
        weekly_hours,
        target_plr,
        target_plr_salary_multiplier,
        target_rvv,
        target_sop,
        target_hiring_sop,
        target_bonus_tech_usd,
        is_active,
        is_time_clocking_required,
        dt_effective_started,
        dt_effective_ended,
        ts_updated,
        object_version_number,
        ROW_NUMBER() OVER (
            PARTITION BY id_job
            ORDER BY dt_effective_started DESC, object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.job
    WHERE
        dt_effective_started < DATE('{load_end_date}')
),
job_latest AS (
    SELECT
        id_job,
        job_code,
        id_job_family,
        contribution_level,
        id_grade_ladder,
        id_set,
        work_arrangement,
        target_sop_currency,
        weekly_hours,
        target_plr,
        target_plr_salary_multiplier,
        target_rvv,
        target_sop,
        target_hiring_sop,
        target_bonus_tech_usd,
        is_active,
        is_time_clocking_required,
        dt_effective_started,
        dt_effective_ended,
        ts_updated,
        object_version_number
    FROM
        job_ranked
    WHERE
        rn = 1
),
job_tl_ranked AS (
    SELECT
        id_job,
        name,
        dt_effective_started,
        object_version_number,
        language,
        ROW_NUMBER() OVER (
            PARTITION BY id_job
            ORDER BY dt_effective_started DESC, object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.job_translation
    WHERE
        dt_effective_started < DATE('{load_end_date}')
        AND language = 'PTB'
),
job_tl_latest AS (
    SELECT
        id_job,
        name,
        dt_effective_started,
        object_version_number,
        language
    FROM
        job_tl_ranked
    WHERE
        rn = 1
),
rate_val_ranked AS (
    SELECT
        id_rate,
        id_rate_object,
        minimum_value,
        maximum_value,
        mid_value,
        dt_effective_started,
        object_version_number,
        ROW_NUMBER() OVER (
            PARTITION BY id_rate, id_rate_object
            ORDER BY dt_effective_started DESC, object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.rate_values
    WHERE
        dt_effective_started < DATE('{load_end_date}')
),
rate_val_latest AS (
    SELECT
        id_rate,
        id_rate_object,
        minimum_value,
        maximum_value,
        mid_value,
        dt_effective_started,
        object_version_number
    FROM
        rate_val_ranked
    WHERE
        rn = 1
),
job_family_tl_ranked AS (
    SELECT
        id_job_family,
        job_family_name,
        dt_effective_started,
        object_version_number,
        ROW_NUMBER() OVER (
            PARTITION BY id_job_family
            ORDER BY dt_effective_started DESC, object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.job_family_translation
    WHERE
        dt_effective_started < DATE('{load_end_date}')
),
job_family_tl_latest AS (
    SELECT
        id_job_family,
        job_family_name,
        dt_effective_started,
        object_version_number
    FROM
        job_family_tl_ranked
    WHERE
        rn = 1
),
job_leg_ranked AS (
    SELECT
        id_job,
        brazilian_occupation_code,
        dt_effective_started,
        object_version_number,
        ROW_NUMBER() OVER (
            PARTITION BY id_job
            ORDER BY dt_effective_started DESC, object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.job_legislative
    WHERE
        dt_effective_started < DATE('{load_end_date}')
),
job_leg_latest AS (
    SELECT
        id_job,
        brazilian_occupation_code,
        dt_effective_started,
        object_version_number
    FROM
        job_leg_ranked
    WHERE
        rn = 1
),
valid_grades_ranked AS (
    SELECT
        id_job,
        id_grade,
        dt_effective_started,
        object_version_number,
        ROW_NUMBER() OVER (
            PARTITION BY id_job
            ORDER BY dt_effective_started DESC, object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.valid_grades
    WHERE
        dt_effective_started < DATE('{load_end_date}')
),
valid_grades_latest AS (
    SELECT
        id_job,
        id_grade,
        dt_effective_started,
        object_version_number
    FROM
        valid_grades_ranked
    WHERE
        rn = 1
),
grade_tl_ranked AS (
    SELECT
        id_grade,
        name,
        dt_effective_started,
        object_version_number,
        ROW_NUMBER() OVER (
            PARTITION BY id_grade
            ORDER BY dt_effective_started DESC, object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.grade_translation
    WHERE
        dt_effective_started < DATE('{load_end_date}')
),
grade_tl_latest AS (
    SELECT
        id_grade,
        name,
        dt_effective_started,
        object_version_number
    FROM
        grade_tl_ranked
    WHERE
        rn = 1
),
grade_ladder_tl_ranked AS (
    SELECT
        id_grade_ladder,
        name,
        dt_effective_started,
        object_version_number,
        ROW_NUMBER() OVER (
            PARTITION BY id_grade_ladder
            ORDER BY dt_effective_started DESC, object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.grade_ladder_translation
    WHERE
        dt_effective_started < DATE('{load_end_date}')
),
grade_ladder_tl_latest AS (
    SELECT
        id_grade_ladder,
        name,
        dt_effective_started,
        object_version_number
    FROM
        grade_ladder_tl_ranked
    WHERE
        rn = 1
),
rates_ranked AS (
    SELECT
        id_grade_ladder,
        id_rate,
        currency_code,
        dt_effective_started,
        object_version_number,
        ROW_NUMBER() OVER (
            PARTITION BY id_grade_ladder, id_rate
            ORDER BY dt_effective_started DESC, object_version_number DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.rates
    WHERE
        dt_effective_started < DATE('{load_end_date}')
),
rates_latest AS (
    SELECT
        id_grade_ladder,
        id_rate,
        currency_code,
        dt_effective_started,
        object_version_number
    FROM
        rates_ranked
    WHERE
        rn = 1
),
set_id_ranked AS (
    SELECT
        id_set,
        set_name,
        language,
        ts_updated,
        ROW_NUMBER() OVER (
            PARTITION BY id_set
            ORDER BY CASE WHEN language = 'PTB' THEN 1 ELSE 2 END, ts_updated DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.set_identifiers
),
set_id_latest AS (
    SELECT
        id_set,
        set_name,
        language,
        ts_updated
    FROM
        set_id_ranked
    WHERE
        rn = 1
)
SELECT
    job_latest.id_job AS sk_job,
    job_latest.job_code,
    job_tl.name AS job_name,
    job_family_tl.job_family_name AS job_category,
    grade_tl.name AS band,
    job_latest.contribution_level AS career_track,
    grade_ladder_tl.name AS comp_ladder_directorate,
    CASE
        WHEN grade_ladder_tl.name = 'Deel' THEN 'Estados Unidos'
        WHEN grade_ladder_tl.name = 'Classifieds Geral' THEN 'Uruguai'
        WHEN RIGHT(grade_ladder_tl.name, 2) = 'PT' THEN 'Portugal'
        WHEN RIGHT(grade_ladder_tl.name, 2) = 'MX' THEN 'Mexico'
        WHEN RIGHT(grade_ladder_tl.name, 3) = 'ARG' THEN 'Argentina'
        WHEN RIGHT(grade_ladder_tl.name, 3) = 'PER' THEN 'Peru'
        WHEN RIGHT(grade_ladder_tl.name, 3) = 'ECU' THEN 'Ecuador'
        WHEN RIGHT(grade_ladder_tl.name, 3) = 'PAN' THEN 'Panama'
        ELSE 'Brasil'
    END AS country,
    set_id.set_name AS comp_ladder_business_unit,
    job_latest.work_arrangement AS working_hours_regime,
    rate.currency_code,
    job_latest.target_sop_currency,
    job_leg.brazilian_occupation_code,
    job_latest.weekly_hours AS workload,
    COALESCE(job_latest.target_plr, 0) AS target_plr,
    COALESCE(job_latest.target_plr_salary_multiplier, 0) AS target_plr_salary_multiplier,
    COALESCE(job_latest.target_rvv, 0) AS target_rvv,
    COALESCE(job_latest.target_sop, 0) AS target_sop,
    COALESCE(job_latest.target_hiring_sop, 0) AS target_hiring_sop,
    COALESCE(job_latest.target_bonus_tech_usd, 0) AS target_bonus_tech_usd,
    rate_val.mid_value AS salary_range_midpoint,
    rate_val.minimum_value AS salary_range_min,
    rate_val.maximum_value AS salary_range_max,
    CASE
        WHEN grade_ladder_tl.name = 'Deel' THEN 12
        WHEN grade_ladder_tl.name = 'Classifieds Geral' THEN 13
        WHEN RIGHT(grade_ladder_tl.name, 2) = 'PT' THEN 14
        WHEN RIGHT(grade_ladder_tl.name, 2) = 'MX' THEN 13
        WHEN RIGHT(grade_ladder_tl.name, 3) = 'ARG' THEN 13
        WHEN RIGHT(grade_ladder_tl.name, 3) = 'PER' THEN 14
        WHEN RIGHT(grade_ladder_tl.name, 3) = 'ECU' THEN 14
        WHEN RIGHT(grade_ladder_tl.name, 3) = 'PAN' THEN 13
        ELSE 13.33
    END AS annual_salary_multiplier,
    job_latest.is_active,
    job_latest.is_time_clocking_required AS has_clock_in,
    job_latest.dt_effective_started AS dt_effective_started,
    job_latest.dt_effective_ended AS dt_effective_ended,
    job_latest.ts_updated AS ts_updated
FROM
    job_latest
LEFT JOIN
    job_tl_latest AS job_tl
        ON job_tl.id_job = job_latest.id_job
LEFT JOIN
    job_family_tl_latest AS job_family_tl
        ON job_family_tl.id_job_family = job_latest.id_job_family
LEFT JOIN
    job_leg_latest AS job_leg
        ON job_leg.id_job = job_latest.id_job
LEFT JOIN
    valid_grades_latest AS valid_grades
        ON valid_grades.id_job = job_latest.id_job
LEFT JOIN
    grade_tl_latest AS grade_tl
        ON grade_tl.id_grade = valid_grades.id_grade
LEFT JOIN
    grade_ladder_tl_latest AS grade_ladder_tl
        ON grade_ladder_tl.id_grade_ladder = job_latest.id_grade_ladder
LEFT JOIN
    set_id_latest AS set_id
        ON job_latest.id_set = set_id.id_set
LEFT JOIN
    rates_latest AS rate
        ON rate.id_grade_ladder = job_latest.id_grade_ladder
LEFT JOIN
    rate_val_latest AS rate_val
        ON rate_val.id_rate = rate.id_rate
        AND rate_val.id_rate_object = valid_grades.id_grade
