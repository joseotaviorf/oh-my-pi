SELECT
    sk_cost_center_version,
    sk_job_version,
    sk_contact_version,
    sk_documentation_version,
    sk_emergency_contact_version,
    sk_employee,
    sk_hierarchy_version,
    sk_business_unit,
    sk_termination_event_definition,
    sk_hired_date,
    sk_terminated_date,
    sk_reference_date,
    person_number,
    assignment_number,
    employment_status,
    tenure_range,
    days_tenure_in_company,
    months_tenure_in_company,
    days_tenure_in_assignment,
    count_direct_report,
    count_indirect_report,
    count_total_report,
    is_member_lt,
    is_member_et,
    is_manager,
    is_active,
    is_terminated,
    has_emergency_contact,
    is_internal_transfer,
    is_primary_assignment_for_snapshot,
    is_reorganization_termination,
    is_monthly_snapshot,
    is_current,
    dt_original_hire,
    dt_hired,
    dt_terminated,
    dt_notified,
    dt_reference,
    ts_load
FROM (
SELECT
    COALESCE(asn.sk_cost_center_version, '-1') AS sk_cost_center_version,
    COALESCE(asn.sk_job_version, '-1') AS sk_job_version,
    COALESCE(ct.sk_contact_version, '-1') AS sk_contact_version,
    COALESCE(doc.sk_documentation_version, '-1') AS sk_documentation_version,
    COALESCE(ec.sk_emergency_contact_version, '-1') AS sk_emergency_contact_version,
    COALESCE(asn.id_person, -1) AS sk_employee,
    COALESCE(asn.sk_hierarchy_version, '-1') AS sk_hierarchy_version,
    COALESCE(asn.id_business_unit, '-1') AS sk_business_unit,
    asn.sk_termination_event_definition,
    asn.sk_hired_date,
    asn.sk_terminated_date,
    asn.sk_reference_date,
    asn.person_number,
    asn.assignment_number,
    asn.employment_status,
    asn.tenure_range,
    asn.days_tenure_in_company,
    asn.months_tenure_in_company,
    asn.days_tenure_in_assignment,
    asn.count_direct_report,
    asn.count_indirect_report,
    asn.count_total_report,
    asn.is_member_lt,
    asn.is_member_et,
    asn.is_manager,
    asn.is_active,
    asn.is_terminated,
    asn.has_emergency_contact,
    asn.is_internal_transfer,
    asn.is_primary_assignment_for_snapshot,
    asn.is_reorganization_termination,
    asn.is_monthly_snapshot,
    asn.dt_reference = CURRENT_DATE() AS is_current,
    asn.dt_original_hire,
    asn.dt_hired,
    asn.dt_terminated,
    asn.dt_notified,
    asn.dt_reference,
    CURRENT_TIMESTAMP() AS ts_load,
  ROW_NUMBER() OVER (PARTITION BY asn.assignment_number, asn.dt_reference ORDER BY ct.sk_contact_version NULLS LAST, doc.sk_documentation_version NULLS LAST, ec.sk_emergency_contact_version NULLS LAST) AS _rn
FROM
    datalake_people.assignment_snapshots AS asn
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
)
WHERE _rn = 1
