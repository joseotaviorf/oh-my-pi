SELECT 
    form_collected_email AS bp_email,
    employee_email,
    dismissal_reason,
    company_evaluation,
    last_semester_evaluation,
    what_should_be_different,
    what_was_more_important,
    specific_difficulties,
    company_culture_evaluation,
    management_evaluation,
    what_should_be_better,
    to_timestamp(timestamp, 'dd/MM/yyyy HH:mm:ss') AS ts_fill_forms,
    ts_load
FROM datalake_gsheets_people_raw.dismissal_forms_bp