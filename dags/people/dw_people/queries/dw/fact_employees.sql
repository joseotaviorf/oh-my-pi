WITH
employee_snapshots AS (
    SELECT
        asn.id_person,
        asn.person_number,
        asn.assignment_number,
        asn.id_organization,
        asn.id_business_unit,
        asn.id_job,
        asn.sk_hired_date,
        asn.sk_terminated_date,
        asn.sk_reference_date,
        asn.dt_reference,
        asn.months_tenure_in_company,
        asn.is_active,
        asn.dt_hired,
        asn.dt_terminated,
        asn.is_current
    FROM
        datalake_people.assignment_snapshots AS asn
    WHERE
        asn.is_monthly_snapshot
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                asn.id_person,
                asn.dt_reference
            ORDER BY
                asn.dt_hired DESC
        ) = 1
)
SELECT
    de.sk_employee,
    COALESCE(bu.sk_business_unit, '-1') AS sk_business_unit,
    COALESCE(j.sk_job_version, '-1') AS sk_job,
    COALESCE(cc.sk_cost_center_version, '-1') AS sk_cost_center_version,
    COALESCE(mh.sk_hierarchy_version, '-1') AS sk_manager_hierarchy,
    es.sk_hired_date,
    CASE
        WHEN es.dt_terminated < CURRENT_DATE() THEN es.sk_terminated_date
        ELSE NULL
    END AS sk_terminated_date,
    es.sk_reference_date,
    j.country AS business_unit_country,
    es.months_tenure_in_company AS tenure_months,
    es.is_active,
    es.is_current,
    es.dt_hired,
    CASE
        WHEN es.dt_terminated < CURRENT_DATE() THEN es.dt_terminated
        ELSE NULL
    END AS dt_terminated,
    es.dt_reference,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    employee_snapshots AS es
INNER JOIN
    dw_employee_details.dim_employee AS de
        ON de.person_number = es.person_number
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON cc.id_organization = es.id_organization
        AND es.dt_reference >= cc.dt_valid_from
        AND es.dt_reference <= COALESCE(
            NULLIF(cc.dt_valid_to, DATE('4712-12-31')),
            DATE('9999-12-31')
        )
LEFT JOIN
    dw_organization.dim_business_unit AS bu
        ON bu.sk_business_unit = es.id_business_unit
LEFT JOIN
    dw_compensation.dim_job AS j
        ON j.id_job = es.id_job
        AND j.is_current = TRUE
LEFT JOIN
    datalake_people.management_hierarchy AS mh
        ON mh.assignment_number = es.assignment_number
        AND mh.is_current = TRUE
