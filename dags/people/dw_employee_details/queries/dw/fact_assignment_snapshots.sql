SELECT
    COALESCE(cc.sk_cost_center_version, '-1') AS sk_cost_center_version,
    COALESCE(j.sk_job_version, '-1') AS sk_job_version,
    COALESCE(ct.sk_contact_version, '-1') AS sk_contact_version,
    COALESCE(doc.sk_documentation_version, '-1') AS sk_documentation_version,
    COALESCE(ec.sk_emergency_contact_version, '-1') AS sk_emergency_contact_version,
    COALESCE(asn.sk_hierarchy_version, '-1') AS sk_hierarchy_version,
    asn.sk_termination_event_definition,
    asn.sk_hired_date,
    asn.sk_terminated_date,
    asn.sk_reference_date,
    asn.person_number,
    asn.assignment_number,
    asn.manager_assignment_number,
    asn.hierarchy_level,
    asn.hierarchy_depth,
    asn.days_tenure_in_company,
    asn.months_tenure_in_company,
    asn.days_tenure_in_assignment,
    asn.count_direct_report,
    asn.count_indirect_report,
    asn.is_member_lt,
    asn.is_member_et,
    asn.is_manager,
    asn.is_active,
    asn.is_terminated,
    asn.has_emergency_contact,
    asn.is_internal_transfer,
    asn.dt_reference = CURRENT_DATE() AS is_current,
    asn.dt_original_hire,
    asn.dt_hired,
    asn.dt_terminated,
    asn.dt_notified,
    asn.dt_reference,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_people.assignment_snapshots AS asn
LEFT JOIN
    dw_organization.dim_cost_center AS cc
        ON cc.id_organization = asn.id_organization
        AND asn.dt_reference >= cc.dt_valid_from
        AND asn.dt_reference <= COALESCE(
            NULLIF(cc.dt_valid_to, DATE('4712-12-31')),
            DATE('9999-12-31')
        )
LEFT JOIN
    dw_compensation.dim_job AS j
        ON j.id_job = asn.id_job
        AND asn.dt_reference >= j.dt_valid_from
        AND asn.dt_reference <= COALESCE(
            NULLIF(j.dt_valid_to, DATE('4712-12-31')),
            DATE('9999-12-31')
        )
LEFT JOIN
    dw_employee_details.dim_contact AS ct
        ON ct.person_number = asn.person_number
        AND asn.dt_reference >= ct.dt_valid_from
        AND asn.dt_reference <= COALESCE(
            NULLIF(ct.dt_valid_to, DATE('4712-12-31')),
            DATE('9999-12-31')
        )
LEFT JOIN
    dw_employee_details.dim_documentation AS doc
        ON doc.person_number = asn.person_number
        AND asn.dt_reference >= doc.dt_valid_from
        AND asn.dt_reference <= COALESCE(
            NULLIF(doc.dt_valid_to, DATE('4712-12-31')),
            DATE('9999-12-31')
        )
LEFT JOIN
    dw_employee_details.dim_emergency_contact AS ec
        ON ec.person_number = asn.person_number
        AND asn.dt_reference >= ec.dt_valid_from
        AND asn.dt_reference <= COALESCE(
            NULLIF(ec.dt_valid_to, DATE('4712-12-31')),
            DATE('9999-12-31')
        )
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY
            asn.assignment_number,
            asn.dt_reference
        ORDER BY
            ct.sk_contact_version NULLS LAST,
            doc.sk_documentation_version NULLS LAST,
            ec.sk_emergency_contact_version NULLS LAST
    ) = 1
