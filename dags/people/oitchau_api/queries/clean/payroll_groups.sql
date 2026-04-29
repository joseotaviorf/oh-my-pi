SELECT
    uuid AS id_payroll_group,
    payrollGroupUuid AS id_payroll_group_business,
    companyUuid AS id_company,
    createdBy AS id_created_by_user,
    name AS payroll_group_name,
    status AS payroll_group_status,
    digitalSignatureStatus AS digital_signature_status,
    userProfilesCount AS count_user_profiles,
    forDeactivatedProfile AS is_for_deactivated_profile,
    startDate AS dt_period_started,
    endDate AS dt_period_ended,
    digitalSignatureStatusChangedAt AS ts_digital_signature_status_changed,
    createdAt AS ts_created,
    reportInsights AS report_insights,
    selectedColumns AS selected_columns,
    ts_load,
    year,
    month,
    day
FROM
    datalake_oitchau_raw.payroll_groups
