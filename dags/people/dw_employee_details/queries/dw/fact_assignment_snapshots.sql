WITH
fact_assignment_snapshots_ranked AS (
    SELECT
        COALESCE(asn.sk_cost_center_version, '-1') AS sk_cost_center_version,
        COALESCE(asn.sk_job_version, '-1') AS sk_job_version,
        COALESCE(asn.sk_compensation_version, '-1') AS sk_compensation_version,
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
        asn.is_leadership_team_member,
        asn.is_executive_team_member,
        asn.is_manager,
        asn.is_active,
        asn.has_emergency_contact,
        asn.is_internal_transfer,
        asn.is_transfer_termination,
        asn.is_primary_assignment_for_snapshot,
        asn.is_reorganization_termination,
        asn.is_monthly_snapshot,
        asn.is_current,
        asn.is_current_for_person,
        asn.dt_original_hire,
        asn.dt_hired,
        asn.dt_terminated,
        asn.dt_notified_termination,
        asn.dt_reference,
        asn.dt_month_reference,
        CURRENT_TIMESTAMP() AS ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY
                asn.assignment_number,
                asn.dt_reference
            ORDER BY
                ct.sk_contact_version NULLS LAST,
                doc.sk_documentation_version NULLS LAST,
                ec.sk_emergency_contact_version NULLS LAST
        ) AS rn
    FROM
        datalake_people.assignment_snapshots AS asn
    LEFT JOIN
        dw_employee_details.dim_contact AS ct
            ON ct.person_number = asn.person_number
            AND asn.dt_reference >= ct.dt_valid_from
            AND asn.dt_reference <= ct.dt_valid_to
    LEFT JOIN
        dw_employee_details.dim_documentation AS doc
            ON doc.person_number = asn.person_number
            AND asn.dt_reference >= doc.dt_valid_from
            AND asn.dt_reference <= doc.dt_valid_to
    LEFT JOIN
        dw_employee_details.dim_emergency_contact AS ec
            ON ec.person_number = asn.person_number
            AND asn.dt_reference >= ec.dt_valid_from
            AND asn.dt_reference <= ec.dt_valid_to
)
SELECT
    sk_cost_center_version,
    sk_job_version,
    sk_compensation_version,
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
    is_leadership_team_member,
    is_executive_team_member,
    is_manager,
    is_active,
    has_emergency_contact,
    is_internal_transfer,
    is_transfer_termination,
    is_primary_assignment_for_snapshot,
    is_reorganization_termination,
    is_monthly_snapshot,
    is_current,
    is_current_for_person,
    dt_original_hire,
    dt_hired,
    dt_terminated,
    dt_notified_termination,
    dt_reference,
    dt_month_reference,
    ts_load
FROM
    fact_assignment_snapshots_ranked
WHERE
    rn = 1
