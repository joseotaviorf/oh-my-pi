WITH salary_bases_history AS (
    SELECT
        id_salary_basis,
        id_grade_rate,
        salary_basis_name,
        salary_basis_code AS salary_frequency,
        salary_basis_type,
        annualization_factor,
        is_active AS salary_basis_is_active,
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
)
SELECT
    MD5(
        CONCAT_WS(
            '|',
            CAST(gl.id_grade_ladder AS STRING),
            CAST(rv.id_rate_object AS STRING),
            CAST(sb.id_salary_basis AS STRING),
            CAST(GREATEST(
                gl.dt_effective_started,
                glt.dt_effective_started,
                gt.dt_effective_started,
                r.dt_effective_started,
                rv.dt_effective_started,
                COALESCE(sb.dt_effective_started, gl.dt_effective_started)
            ) AS STRING)
        )
    ) AS sk_salary_table,
    glt.name AS salary_table,
    gt.name AS band,
    CASE
        WHEN glt.name = 'Deel' THEN 'Estados Unidos'
        WHEN glt.name = 'Classifieds Geral' THEN 'Uruguai'
        WHEN RIGHT(glt.name, 2) = 'PT' THEN 'Portugal'
        WHEN RIGHT(glt.name, 2) = 'MX' THEN 'Mexico'
        WHEN RIGHT(glt.name, 3) = 'ARG' THEN 'Argentina'
        WHEN RIGHT(glt.name, 3) = 'PER' THEN 'Peru'
        WHEN RIGHT(glt.name, 3) = 'ECU' THEN 'Ecuador'
        WHEN RIGHT(glt.name, 3) = 'PAN' THEN 'Panama'
        ELSE 'Brasil'
    END AS country,
    CASE
        WHEN glt.name IN ('Deel', 'Classifieds Geral')
            OR RIGHT(glt.name, 2) IN ('PT', 'MX')
            OR RIGHT(glt.name, 3) IN ('ARG', 'PER', 'ECU', 'PAN')
            THEN CASE
                WHEN glt.name = 'Deel' THEN 'Estados Unidos'
                WHEN glt.name = 'Classifieds Geral' THEN 'Uruguai'
                WHEN RIGHT(glt.name, 2) = 'PT' THEN 'Portugal'
                WHEN RIGHT(glt.name, 2) = 'MX' THEN 'Mexico'
                WHEN RIGHT(glt.name, 3) = 'ARG' THEN 'Argentina'
                WHEN RIGHT(glt.name, 3) = 'PER' THEN 'Peru'
                WHEN RIGHT(glt.name, 3) = 'ECU' THEN 'Ecuador'
                WHEN RIGHT(glt.name, 3) = 'PAN' THEN 'Panama'
            END
        WHEN LEFT(gt.name, 5) = 'Estag' THEN 'Estag'
        WHEN LEFT(gt.name, 2) = 'JA' THEN 'JA'
        WHEN LEFT(glt.name, 8) = 'Ops Sale' THEN 'Ops Sale'
        WHEN SPLIT_PART(glt.name, ' ', 1) IN ('PM', 'DA', 'Eng', 'Prod', 'DSR', 'Growth')
            THEN SPLIT_PART(glt.name, ' ', 1)
        WHEN CAST(gt.name AS INT) >= 12 THEN 'EXEC'
        ELSE SPLIT_PART(glt.name, ' ', 1)
    END AS salary_table_group,
    sb.salary_basis_name,
    sb.salary_frequency,
    sb.salary_basis_type,
    sb.annualization_factor,
    r.currency_code AS salary_range_currency,
    CAST(rv.minimum_value AS DECIMAL(18, 2)) AS minimum_value,
    CAST(rv.mid_value AS DECIMAL(18, 2)) AS mid_value,
    CAST(rv.maximum_value AS DECIMAL(18, 2)) AS maximum_value,
    gl.is_active,
    GREATEST(
        gl.dt_effective_started,
        glt.dt_effective_started,
        gt.dt_effective_started,
        r.dt_effective_started,
        rv.dt_effective_started,
        COALESCE(sb.dt_effective_started, gl.dt_effective_started)
    ) AS dt_valid_from,
    NULLIF(
        LEAST(
            gl.dt_effective_ended,
            glt.dt_effective_ended,
            gt.dt_effective_ended,
            r.dt_effective_ended,
            rv.dt_effective_ended,
            COALESCE(sb.dt_effective_ended, DATE('4712-12-31'))
        ),
        DATE('4712-12-31')
    ) AS dt_valid_to,
    -- is_current: TRUE if load_end_date falls within [dt_valid_from, dt_valid_to)
    (
        DATE('{load_end_date}') >= GREATEST(
            gl.dt_effective_started,
            glt.dt_effective_started,
            gt.dt_effective_started,
            r.dt_effective_started,
            rv.dt_effective_started,
            COALESCE(sb.dt_effective_started, gl.dt_effective_started)
        )
        AND DATE('{load_end_date}') < LEAST(
            gl.dt_effective_ended,
            glt.dt_effective_ended,
            gt.dt_effective_ended,
            r.dt_effective_ended,
            rv.dt_effective_ended,
            COALESCE(sb.dt_effective_ended, DATE('4712-12-31'))
        )
    ) AS is_current,
    NOW() AS ts_load
FROM
    datalake_pin_core_clean.grade_ladder AS gl
INNER JOIN
    datalake_pin_core_clean.grade_ladder_translation AS glt
        ON glt.id_grade_ladder = gl.id_grade_ladder
        AND glt.language = 'PTB'
        AND gl.dt_effective_started < glt.dt_effective_ended
        AND gl.dt_effective_ended > glt.dt_effective_started
INNER JOIN
    datalake_pin_core_clean.rates AS r
        ON r.id_grade_ladder = gl.id_grade_ladder
        AND gl.dt_effective_started < r.dt_effective_ended
        AND gl.dt_effective_ended > r.dt_effective_started
INNER JOIN
    datalake_pin_core_clean.rate_values AS rv
        ON rv.id_rate = r.id_rate
        AND gl.dt_effective_started < rv.dt_effective_ended
        AND gl.dt_effective_ended > rv.dt_effective_started
INNER JOIN
    datalake_pin_core_clean.grade_translation AS gt
        ON gt.id_grade = rv.id_rate_object
        AND gt.language = 'PTB'
        AND gl.dt_effective_started < gt.dt_effective_ended
        AND gl.dt_effective_ended > gt.dt_effective_started
LEFT JOIN
    salary_bases_history AS sb
        ON sb.id_grade_rate = r.id_rate
        AND r.dt_effective_started < sb.dt_effective_ended
        AND r.dt_effective_ended > sb.dt_effective_started
WHERE
    -- This excludes future records that haven't started yet
    gl.dt_effective_started <= DATE('{load_end_date}')
    AND glt.dt_effective_started <= DATE('{load_end_date}')
    AND gt.dt_effective_started <= DATE('{load_end_date}')
    AND r.dt_effective_started <= DATE('{load_end_date}')
    AND rv.dt_effective_started <= DATE('{load_end_date}')
    -- Ensure valid date overlap between all tables
    AND GREATEST(
        gl.dt_effective_started,
        glt.dt_effective_started,
        gt.dt_effective_started,
        r.dt_effective_started,
        rv.dt_effective_started,
        COALESCE(sb.dt_effective_started, gl.dt_effective_started)
    ) < LEAST(
        gl.dt_effective_ended,
        glt.dt_effective_ended,
        gt.dt_effective_ended,
        r.dt_effective_ended,
        rv.dt_effective_ended,
        COALESCE(sb.dt_effective_ended, DATE('4712-12-31'))
    )
