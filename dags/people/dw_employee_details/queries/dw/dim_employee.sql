WITH
employees AS (
    SELECT
        im.id_person,
        im.person_number,
        im.name,
        im.work_email,
        im.employee_tmf_code
    FROM
        datalake_people.identifier_mapping AS im
    WHERE
        NOT im.is_user_test
        AND im.assignment_type IN ('C', 'E')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                im.id_person
            ORDER BY
                im.assignment_number
        ) = 1
),
current_education AS (
    SELECT
        pl.id_person,
        flv.meaning AS highest_education_level
    FROM
        datalake_pin_core_clean.people_legislative AS pl
    LEFT JOIN
        datalake_pin_core_clean.foundation_lookup_value AS flv
        ON CAST(pl.highest_education_level AS STRING) = flv.lookup_code
        AND flv.lookup_type = 'PER_HIGHEST_EDUCATION_LEVEL'
        AND flv.language = 'US'
    WHERE
        pl.legislation_code = 'BR'
        AND (
            pl.dt_effective_ended IS NULL
            OR pl.dt_effective_ended >= CURRENT_DATE()
        )
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                pl.id_person
            ORDER BY
                pl.dt_effective_started DESC
        ) = 1
)
SELECT
    emp.id_person AS sk_employee,
    emp.person_number,
    emp.name AS name,
    emp.work_email,
    emp.employee_tmf_code,
    ce.highest_education_level,
    CASE
        WHEN p.dt_of_birth IS NULL THEN NULL
        WHEN YEAR(p.dt_of_birth) BETWEEN 1928 AND 1945 THEN 'Silent Generation'
        WHEN YEAR(p.dt_of_birth) BETWEEN 1946 AND 1964 THEN 'Baby Boomers'
        WHEN YEAR(p.dt_of_birth) BETWEEN 1965 AND 1980 THEN 'Generation X'
        WHEN YEAR(p.dt_of_birth) BETWEEN 1981 AND 1996 THEN 'Millennials'
        WHEN YEAR(p.dt_of_birth) BETWEEN 1997 AND 2012 THEN 'Generation Z'
        WHEN YEAR(p.dt_of_birth) BETWEEN 2013 AND 2024 THEN 'Generation Alpha'
    END AS generation,
    p.dt_of_birth AS dt_birth,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    employees AS emp
LEFT JOIN
    datalake_pin_core_clean.person AS p
    ON emp.id_person = p.id_person
LEFT JOIN
    current_education AS ce
    ON emp.id_person = ce.id_person
