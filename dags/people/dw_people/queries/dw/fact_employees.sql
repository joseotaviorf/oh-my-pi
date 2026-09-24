SELECT
    asn.id_person AS sk_employee,
    COALESCE(asn.id_business_unit, '-1') AS sk_business_unit,
    COALESCE(asn.id_job, '-1') AS sk_job,
    COALESCE(asn.sk_cost_center_version, '-1') AS sk_cost_center_version,
    COALESCE(asn.sk_hierarchy_version, '-1') AS sk_manager_hierarchy,
    DATE_FORMAT(asn.dt_employee_hired, 'yyyyMMdd') AS sk_employee_hired_date,
    asn.sk_reference_date,
    asn.business_unit_country,
    asn.months_employee_tenure,
    asn.dt_employee_hired,
    asn.dt_reference,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_people.assignment_snapshots AS asn
WHERE
    asn.is_current_for_employee
    AND asn.is_active
