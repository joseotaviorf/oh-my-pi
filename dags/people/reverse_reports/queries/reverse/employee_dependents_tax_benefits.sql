-- Grain: one current contact relationship per employee and dependent, restricted to IRRF or family-allowance dependents.
WITH current_relationships AS (
    SELECT
        id_person,
        id_contact_person,
        contact_type,
        irrf_dependent_type_code,
        family_allowance_dependent_type_code,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_person,
                id_contact_person
            ORDER BY
                dt_effective_ended DESC,
                dt_effective_started DESC,
                id_contact_relationship DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.contact_relationship
    WHERE
        dt_effective_started <= DATE('{load_start_date}')
        AND dt_effective_ended >= DATE('{load_start_date}')
        AND (
            irrf_dependent_type_code IS NOT NULL
            OR family_allowance_dependent_type_code IS NOT NULL
        )
),
employees AS (
    SELECT
        sk_employee,
        person_number,
        name,
        cpf,
        work_email,
        is_active,
        business_unit_name,
        structure
    FROM
        metric_people.employee_snapshots
    WHERE
        is_current_for_employee = TRUE
        AND (
            is_active = TRUE
            OR dt_terminated >= ADD_MONTHS(DATE('{load_start_date}'), -12)
        )
),
dependent_names AS (
    SELECT
        id_person,
        documented_full_name,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_person
            ORDER BY
                dt_effective_ended DESC,
                dt_effective_started DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.person_name
    WHERE
        name_type = 'GLOBAL'
        AND dt_effective_started <= DATE('{load_start_date}')
        AND dt_effective_ended >= DATE('{load_start_date}')
),
dependent_cpfs AS (
    SELECT
        id_person,
        national_identifier_number AS cpf,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_person
            ORDER BY
                ts_updated DESC,
                id_national_identifier DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.national_identifiers
    WHERE
        national_identifier_type = 'CPF'
),
dependent_births AS (
    SELECT
        id_person,
        dt_of_birth,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_person
            ORDER BY
                ts_updated DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.person
),
lookups AS (
    SELECT
        lookup_type,
        lookup_code,
        meaning,
        -- IRRF codes 4 and 6 and family-allowance code 3 are the PIN "not a dependent" values.
        NOT (
            (lookup_type = 'QA_DEPENDENTE_IRRF' AND lookup_code IN ('4', '6'))
            OR (lookup_type = 'QA_SALARIO_FAMILIA' AND lookup_code = '3')
        ) AS is_dependent_type
    FROM
        datalake_pin_core_clean.foundation_lookup_value
    WHERE
        lookup_type IN ('QA_CONTATO_EMERGENCIA', 'QA_DEPENDENTE_IRRF', 'QA_SALARIO_FAMILIA')
        AND language = 'PTB'
        -- Disabled tax codes stay because existing relationships still carry them.
        AND (
            is_enabled = TRUE
            OR lookup_type IN ('QA_DEPENDENTE_IRRF', 'QA_SALARIO_FAMILIA')
        )
)
SELECT
    emp.person_number,
    emp.name AS employee_name,
    emp.cpf AS employee_cpf,
    LOWER(emp.work_email) AS employee_email,
    CASE
        WHEN emp.is_active = TRUE THEN 'ativo'
        ELSE 'inativo'
    END AS employee_status,
    emp.business_unit_name AS empresa,
    NULLIF(LOWER(emp.structure), '-1') AS structure,
    dn.documented_full_name AS dependent_name,
    dc.cpf AS dependent_cpf,
    db.dt_of_birth AS dependent_birth_date,
    COALESCE(lk_contact.meaning, cr.contact_type) AS relationship_degree,
    lk_irrf.meaning AS irrf_dependent_type,
    COALESCE(lk_irrf.is_dependent_type, FALSE) AS is_irrf_dependent,
    lk_fa.meaning AS family_allowance_dependent_type,
    COALESCE(lk_fa.is_dependent_type, FALSE) AS is_family_allowance_dependent,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    current_relationships AS cr
INNER JOIN
    employees AS emp
        ON emp.sk_employee = cr.id_person
LEFT JOIN
    dependent_names AS dn
        ON dn.id_person = cr.id_contact_person
        AND dn.rn = 1
LEFT JOIN
    dependent_cpfs AS dc
        ON dc.id_person = cr.id_contact_person
        AND dc.rn = 1
LEFT JOIN
    dependent_births AS db
        ON db.id_person = cr.id_contact_person
        AND db.rn = 1
LEFT JOIN
    lookups AS lk_contact
        ON lk_contact.lookup_code = cr.contact_type
        AND lk_contact.lookup_type = 'QA_CONTATO_EMERGENCIA'
LEFT JOIN
    lookups AS lk_irrf
        ON lk_irrf.lookup_code = cr.irrf_dependent_type_code
        AND lk_irrf.lookup_type = 'QA_DEPENDENTE_IRRF'
LEFT JOIN
    lookups AS lk_fa
        ON lk_fa.lookup_code = cr.family_allowance_dependent_type_code
        AND lk_fa.lookup_type = 'QA_SALARIO_FAMILIA'
WHERE
    cr.rn = 1
    AND (
        lk_irrf.is_dependent_type = TRUE
        OR lk_fa.is_dependent_type = TRUE
    )
