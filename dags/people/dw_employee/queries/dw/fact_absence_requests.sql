SELECT
    id_per_absence_entry AS sk_absence_request,
    id_period_of_service AS sk_assignment,
    id_absence_type AS sk_absence_type,
    MD5(approval_status_code) AS sk_request_status,
    COALESCE(DATE_FORMAT(ts_approved, 'yyyyMMdd'), -1) AS sk_revision_date,
    COALESCE(DATE_FORMAT(dt_submitted, 'yyyyMMdd'), -1) AS sk_request_date,
    COALESCE(DATE_FORMAT(dt_notificated, 'yyyyMMdd'), -1) AS sk_notification_date,
    COALESCE(DATE_FORMAT(dt_started, 'yyyyMMdd'), -1) AS sk_absence_started_date,
    COALESCE(DATE_FORMAT(dt_ended, 'yyyyMMdd'), -1) AS sk_absence_ended_date,
    days_duration AS days_requested,
    CASE 
        WHEN id_absence_type = 300000004800809 
        THEN COALESCE(vacation_cash_out_request, 0) 
        ELSE -1 
    END AS days_vacation_cash_out,
    IF(id_absence_type = 300000004800809, TRUE, FALSE) AS is_vacation_request,
    approval_status_code = 'APPROVED' AS is_approved,
    approval_status_code = 'DENIED' AS is_denied,
    approval_status_code = 'AWAITING' AS is_pending,
    is_open_ended,
    IF(vacation_cash_out_request IS NOT NULL, TRUE, FALSE) AS has_requested_vacation_cash_out,
    CASE advance_13th_salary
        WHEN 'S' THEN TRUE 
        WHEN 'N' THEN FALSE 
    END AS has_requested_13th_salary_advance,
    NOW() AS ts_load
FROM
    datalake_pin_absence_clean.person_entry
QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY id_per_absence_entry ORDER BY object_version_number DESC) = 1