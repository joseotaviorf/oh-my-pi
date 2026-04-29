SELECT
    payrollLockUuid AS id_payroll_lock,
    payrollLayoutUuid AS id_payroll_layout,
    companyUuid AS id_company,
    createdBy AS id_created_by_user,
    status AS payroll_run_status,
    startDate AS dt_period_started,
    endDate AS dt_period_ended,
    sendToPayrollRequestedAt AS ts_send_to_payroll_requested,
    sentToPayrollAt AS ts_sent_to_payroll,
    updatedAt AS ts_updated,
    fileUrls AS payroll_file_urls,
    payrollLayout AS payroll_layout,
    report AS payroll_report_rows,
    ts_load,
    year,
    month,
    day
FROM
    datalake_oitchau_raw.payroll
