WITH salary_bases_history AS (
    SELECT
        id_salary_basis,
        id_grade_rate,
        salary_basis_name,
        salary_basis_code AS salary_frequency,
        salary_basis_type,
        annualization_factor,
        object_version_number,
        dt_available_from AS dt_effective_started,
        COALESCE(
            LEAD(dt_available_from) OVER (
                PARTITION BY id_salary_basis
                ORDER BY object_version_number
            ),
            DATE('9999-12-31')
        ) AS dt_effective_ended
    FROM
        datalake_pin_compensation_clean.salary_bases
    WHERE
        dt_available_from <= DATE('{load_start_date}')
),
job_with_salary_table_base_ranked AS (
    SELECT
        j.id_job,
        j.job_code,
        jt.name AS job_name,
        jft.job_family_name AS job_family,
        gt.name AS band,
        j.contribution_level AS career_track,
        CASE
            WHEN j.contribution_level = 'Líder'
            THEN TRUE
            ELSE FALSE
        END AS is_leadership_job,
        CASE
            WHEN gt.name = 'EXEC' OR TRY_CAST(gt.name AS INT) >= 10
            THEN TRUE
            ELSE FALSE
        END AS is_leadership_team_job,
        si.set_name AS job_business_unit_group,
        glt.name AS salary_table,
        CASE
            WHEN glt.name = 'Deel'
                THEN 'United States'
            WHEN glt.name = 'Classifieds Geral'
                THEN 'Uruguay'
            WHEN RIGHT(glt.name, 2) = 'PT'
                OR glt.name LIKE '% PT'
                THEN 'Portugal'
            WHEN RIGHT(glt.name, 2) = 'MX'
                OR glt.name LIKE '% MX'
                THEN 'Mexico'
            WHEN RIGHT(glt.name, 3) = 'ARG'
                OR glt.name LIKE '% ARG'
                THEN 'Argentina'
            WHEN RIGHT(glt.name, 3) = 'PER'
                OR glt.name LIKE '% PER'
                THEN 'Peru'
            WHEN RIGHT(glt.name, 3) = 'ECU'
                OR glt.name LIKE '% ECU'
                THEN 'Ecuador'
            WHEN RIGHT(glt.name, 3) = 'PAN'
                OR glt.name LIKE '% PAN'
                THEN 'Panama'
            ELSE 'Brazil'
        END AS country,
        CASE
            WHEN glt.name IN ('Deel', 'Classifieds Geral')
                OR RIGHT(glt.name, 2) = 'PT'
                OR glt.name LIKE '% PT'
                OR RIGHT(glt.name, 2) = 'MX'
                OR glt.name LIKE '% MX'
                OR RIGHT(glt.name, 3) = 'ARG'
                OR glt.name LIKE '% ARG'
                OR RIGHT(glt.name, 3) = 'PER'
                OR glt.name LIKE '% PER'
                OR RIGHT(glt.name, 3) = 'ECU'
                OR glt.name LIKE '% ECU'
                OR RIGHT(glt.name, 3) = 'PAN'
                OR glt.name LIKE '% PAN'
                THEN CASE
                    WHEN glt.name = 'Deel'
                        THEN 'United States'
                    WHEN glt.name = 'Classifieds Geral'
                        THEN 'Uruguay'
                    WHEN RIGHT(glt.name, 2) = 'PT'
                        OR glt.name LIKE '% PT'
                        THEN 'Portugal'
                    WHEN RIGHT(glt.name, 2) = 'MX'
                        OR glt.name LIKE '% MX'
                        THEN 'Mexico'
                    WHEN RIGHT(glt.name, 3) = 'ARG'
                        OR glt.name LIKE '% ARG'
                        THEN 'Argentina'
                    WHEN RIGHT(glt.name, 3) = 'PER'
                        OR glt.name LIKE '% PER'
                        THEN 'Peru'
                    WHEN RIGHT(glt.name, 3) = 'ECU'
                        OR glt.name LIKE '% ECU'
                        THEN 'Ecuador'
                    WHEN RIGHT(glt.name, 3) = 'PAN'
                        OR glt.name LIKE '% PAN'
                        THEN 'Panama'
                END
            WHEN LEFT(COALESCE(gt_ptb.name, gt.name), 5) = 'Estag'
                THEN 'Estag'
            WHEN LEFT(COALESCE(gt_ptb.name, gt.name), 2) = 'JA'
                THEN 'JA'
            WHEN LEFT(glt.name, 8) = 'Ops Sale'
                THEN 'Ops Sale'
            WHEN SPLIT_PART(glt.name, ' ', 1) IN ('PM', 'DA', 'Eng', 'Prod', 'DSR', 'Growth')
                THEN SPLIT_PART(glt.name, ' ', 1)
            WHEN TRY_CAST(COALESCE(gt_ptb.name, gt.name) AS INT) >= 12
                THEN 'EXEC'
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
        sb.annualization_factor,
        COALESCE(j.target_plr, 0) AS target_plr,
        COALESCE(j.target_plr_salary_multiplier, 0) AS target_plr_salary_multiplier,
        COALESCE(j.target_rvv, 0) AS target_rvv,
        COALESCE(j.target_sop, 0) AS target_sop,
        COALESCE(j.target_hiring_sop, 0) AS target_hiring_sop,
        COALESCE(j.target_bonus_tech_usd, 0) AS target_exceptional_bonus,
        CAST(rv.minimum_value AS DECIMAL(18, 2)) AS salary_range_min,
        CAST(rv.mid_value AS DECIMAL(18, 2)) AS salary_range_mid,
        CAST(rv.maximum_value AS DECIMAL(18, 2)) AS salary_range_max,
        j.is_time_clocking_required AS has_clock_in,
        j.is_active,
        GREATEST(
            j.dt_effective_started,
            COALESCE(vg.dt_effective_started, j.dt_effective_started),
            COALESCE(gl.dt_effective_started, j.dt_effective_started),
            COALESCE(glt.dt_effective_started, j.dt_effective_started),
            COALESCE(gt.dt_effective_started, j.dt_effective_started),
            COALESCE(gt_ptb.dt_effective_started, j.dt_effective_started),
            COALESCE(r.dt_effective_started, j.dt_effective_started),
            COALESCE(rv.dt_effective_started, j.dt_effective_started),
            COALESCE(sb.dt_effective_started, j.dt_effective_started)
        ) AS dt_valid_from,
        LEAST(
            j.dt_effective_ended,
            COALESCE(vg.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(gl.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(glt.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(gt.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(gt_ptb.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(r.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(rv.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(sb.dt_effective_ended, DATE('9999-12-31'))
        ) AS dt_valid_to,
        ROW_NUMBER() OVER (
            PARTITION BY
                j.id_job,
                GREATEST(
                    j.dt_effective_started,
                    COALESCE(vg.dt_effective_started, j.dt_effective_started),
                    COALESCE(gl.dt_effective_started, j.dt_effective_started),
                    COALESCE(glt.dt_effective_started, j.dt_effective_started),
                    COALESCE(gt.dt_effective_started, j.dt_effective_started),
                    COALESCE(gt_ptb.dt_effective_started, j.dt_effective_started),
                    COALESCE(r.dt_effective_started, j.dt_effective_started),
                    COALESCE(rv.dt_effective_started, j.dt_effective_started),
                    COALESCE(sb.dt_effective_started, j.dt_effective_started)
                )
            ORDER BY
                jt.dt_effective_started DESC NULLS LAST,
                jt.object_version_number DESC NULLS LAST,
                jft.dt_effective_started DESC NULLS LAST,
                jft.object_version_number DESC NULLS LAST,
                gt.dt_effective_started DESC NULLS LAST,
                gt.object_version_number DESC NULLS LAST,
                gt_ptb.dt_effective_started DESC NULLS LAST,
                gt_ptb.object_version_number DESC NULLS LAST,
                glt.dt_effective_started DESC NULLS LAST,
                glt.object_version_number DESC NULLS LAST,
                gl.dt_effective_started DESC NULLS LAST,
                si.ts_updated DESC NULLS LAST,
                jl.dt_effective_started DESC NULLS LAST,
                jl.object_version_number DESC NULLS LAST,
                vg.dt_effective_started DESC NULLS LAST,
                vg.object_version_number DESC NULLS LAST,
                r.dt_effective_started DESC NULLS LAST,
                r.object_version_number DESC NULLS LAST,
                rv.dt_effective_started DESC NULLS LAST,
                rv.object_version_number DESC NULLS LAST,
                sb.dt_effective_started DESC NULLS LAST,
                sb.object_version_number DESC NULLS LAST
        ) AS rn
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
        datalake_pin_core_clean.valid_grades AS vg
            ON vg.id_job = j.id_job
            AND j.dt_effective_started < COALESCE(vg.dt_effective_ended, DATE('9999-12-31'))
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
            AND si.language = 'US'
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
        datalake_pin_core_clean.rates AS r
            ON r.id_grade_ladder = j.id_grade_ladder
            AND r.rate_type = 'SALARY'
            AND j.dt_effective_started < r.dt_effective_ended
            AND j.dt_effective_ended > r.dt_effective_started
    LEFT JOIN
        datalake_pin_core_clean.rate_values AS rv
            ON rv.id_rate = r.id_rate
            AND rv.id_rate_object = vg.id_grade
            AND j.dt_effective_started < rv.dt_effective_ended
            AND j.dt_effective_ended > rv.dt_effective_started
    LEFT JOIN
        salary_bases_history AS sb
            ON sb.id_grade_rate = r.id_rate
            AND j.dt_effective_started < sb.dt_effective_ended
            AND j.dt_effective_ended > sb.dt_effective_started
    WHERE
        j.dt_effective_started <= DATE('{load_start_date}')
        AND (
            vg.dt_effective_started IS NULL
            OR vg.dt_effective_started <= DATE('{load_start_date}')
        )
        AND (
            gl.dt_effective_started IS NULL
            OR gl.dt_effective_started <= DATE('{load_start_date}')
        )
        AND (
            glt.dt_effective_started IS NULL
            OR glt.dt_effective_started <= DATE('{load_start_date}')
        )
        AND (
            gt.dt_effective_started IS NULL
            OR gt.dt_effective_started <= DATE('{load_start_date}')
        )
        AND (
            gt_ptb.dt_effective_started IS NULL
            OR gt_ptb.dt_effective_started <= DATE('{load_start_date}')
        )
        AND (
            r.dt_effective_started IS NULL
            OR r.dt_effective_started <= DATE('{load_start_date}')
        )
        AND (
            rv.dt_effective_started IS NULL
            OR rv.dt_effective_started <= DATE('{load_start_date}')
        )
        AND (
            sb.dt_effective_started IS NULL
            OR sb.dt_effective_started <= DATE('{load_start_date}')
        )
        AND GREATEST(
            j.dt_effective_started,
            COALESCE(vg.dt_effective_started, j.dt_effective_started),
            COALESCE(gl.dt_effective_started, j.dt_effective_started),
            COALESCE(glt.dt_effective_started, j.dt_effective_started),
            COALESCE(gt.dt_effective_started, j.dt_effective_started),
            COALESCE(gt_ptb.dt_effective_started, j.dt_effective_started),
            COALESCE(r.dt_effective_started, j.dt_effective_started),
            COALESCE(rv.dt_effective_started, j.dt_effective_started),
            COALESCE(sb.dt_effective_started, j.dt_effective_started)
        ) < LEAST(
            j.dt_effective_ended,
            COALESCE(vg.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(gl.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(glt.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(gt.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(gt_ptb.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(r.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(rv.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(sb.dt_effective_ended, DATE('9999-12-31'))
        )
),
job_with_salary_table_base AS (
    SELECT * FROM job_with_salary_table_base_ranked WHERE rn = 1
),
job_with_salary_table_with_hash AS (
    SELECT
        *,
        MD5(CONCAT_WS('|',
            CAST(id_job AS STRING),
            CAST(job_code AS STRING),
            CAST(job_name AS STRING),
            CAST(job_family AS STRING),
            CAST(band AS STRING),
            CAST(career_track AS STRING),
            CAST(is_leadership_job AS STRING),
            CAST(is_leadership_team_job AS STRING),
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
            CAST(is_active AS STRING),
            CAST(annualization_factor AS STRING),
            CAST(target_plr AS STRING),
            CAST(target_plr_salary_multiplier AS STRING),
            CAST(target_rvv AS STRING),
            CAST(target_sop AS STRING),
            CAST(target_hiring_sop AS STRING),
            CAST(target_exceptional_bonus AS STRING),
            CAST(salary_range_min AS STRING),
            CAST(salary_range_mid AS STRING),
            CAST(salary_range_max AS STRING)
        )) AS attributes_hash
    FROM
        job_with_salary_table_base
),
job_with_salary_table_groups AS (
    SELECT
        *,
        SUM(
            CASE
                WHEN LAG(attributes_hash) OVER (
                    PARTITION BY id_job
                    ORDER BY dt_valid_from
                ) <> attributes_hash
                    OR LAG(attributes_hash) OVER (
                        PARTITION BY id_job
                        ORDER BY dt_valid_from
                    ) IS NULL
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_job
            ORDER BY dt_valid_from
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS change_group
    FROM
        job_with_salary_table_with_hash
),
job_with_salary_table_consolidated AS (
    SELECT
        id_job,
        job_code,
        job_name,
        job_family,
        band,
        career_track,
        is_leadership_job,
        is_leadership_team_job,
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
        MIN(dt_valid_from) AS dt_valid_from,
        MAX(dt_valid_to) AS dt_valid_to,
        NOW() AS ts_load
    FROM
        job_with_salary_table_groups
    GROUP BY
        id_job,
        job_code,
        job_name,
        job_family,
        band,
        career_track,
        is_leadership_job,
        is_leadership_team_job,
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
    id_job,
    job_code,
    job_name,
    job_family,
    band,
    career_track,
    is_leadership_job,
    is_leadership_team_job,
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
    CASE
        WHEN DATE('{load_start_date}') >= dt_valid_from
            AND (
                dt_valid_to IS NULL
                OR DATE('{load_start_date}') < dt_valid_to
            )
        THEN TRUE
        ELSE FALSE
    END AS is_current,
    dt_valid_from,
    dt_valid_to,
    ts_load
FROM
    job_with_salary_table_consolidated
