SELECT
    asn.id_person AS sk_employee,
    COALESCE(asn.id_business_unit, '-1') AS sk_business_unit,
    COALESCE(asn.sk_job_version, '-1') AS sk_job,
    COALESCE(asn.sk_cost_center_version, '-1') AS sk_cost_center_version,
    COALESCE(asn.sk_hierarchy_version, '-1') AS sk_manager_hierarchy,
    asn.sk_hired_date,
    CASE
        WHEN asn.dt_terminated <= DATE('{load_start_date}') THEN asn.sk_terminated_date
        ELSE NULL
    END AS sk_terminated_date,
    asn.sk_reference_date,
    asn.business_unit_country,
    asn.months_tenure_in_company AS tenure_months,
    asn.is_active,
    asn.is_current_for_assignment AS is_current,
    asn.dt_hired,
    CASE
        WHEN asn.dt_terminated <= DATE('{load_start_date}') THEN asn.dt_terminated
        ELSE NULL
    END AS dt_terminated,
    asn.dt_reference,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_people.assignment_snapshots AS asn
WHERE
    asn.is_monthly_snapshot_for_employee
