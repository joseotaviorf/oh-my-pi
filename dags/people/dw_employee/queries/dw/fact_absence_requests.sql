SELECT
    sk_absence_request,
    sk_assignment,
    sk_absence_type,
    sk_absence_request_status,
    sk_revision_date,
    sk_request_date,
    sk_notification_date,
    sk_absence_started_date,
    sk_absence_ended_date,
    request_comments,
    days_requested,
    days_vacation_cash_out,
    is_vacation_request,
    is_approved,
    is_denied,
    is_pending,
    is_withdrawn,
    is_open_ended,
    has_requested_vacation_cash_out,
    has_requested_13th_salary_advance,
    dt_requested,
    dt_notificated,
    dt_absence_started,
    dt_absence_ended,
    ts_approved,
    ts_load
FROM (
SELECT
    id_per_absence_entry AS sk_absence_request,
    id_period_of_service AS sk_assignment,
    id_absence_type AS sk_absence_type,
    MD5(CONCAT(COALESCE(approval_status_code, ''), '|', COALESCE(absence_status_code, ''))) AS sk_absence_request_status,
    COALESCE(DATE_FORMAT(ts_approved, 'yyyyMMdd'), -1) AS sk_revision_date,
    COALESCE(DATE_FORMAT(dt_submitted, 'yyyyMMdd'), -1) AS sk_request_date,
    COALESCE(DATE_FORMAT(dt_notificated, 'yyyyMMdd'), -1) AS sk_notification_date,
    COALESCE(DATE_FORMAT(dt_started, 'yyyyMMdd'), -1) AS sk_absence_started_date,
    COALESCE(DATE_FORMAT(dt_ended, 'yyyyMMdd'), -1) AS sk_absence_ended_date,
    comments AS request_comments,
    days_duration AS days_requested,
    CASE
        WHEN id_absence_type = 300000004800809
        THEN COALESCE(vacation_cash_out_request, 0)
        ELSE -1
    END AS days_vacation_cash_out,
    IF(id_absence_type = 300000004800809, TRUE, FALSE) AS is_vacation_request,
    approval_status_code = 'APPROVED' AND absence_status_code <> 'ORA_WITHDRAWN' AS is_approved,
    approval_status_code = 'DENIED' AND absence_status_code <> 'ORA_WITHDRAWN' AS is_denied,
    approval_status_code IN ('AWAITING', 'ORA_AWAIT_AWAIT') AND absence_status_code <> 'ORA_WITHDRAWN' AS is_pending,
    absence_status_code = 'ORA_WITHDRAWN' AS is_withdrawn,
    is_open_ended,
    IF(vacation_cash_out_request IS NOT NULL, TRUE, FALSE) AS has_requested_vacation_cash_out,
    CASE advance_13th_salary
        WHEN 'S' THEN TRUE
        WHEN 'N' THEN FALSE
    END AS has_requested_13th_salary_advance,
    dt_submitted AS dt_requested,
    dt_notificated AS dt_notificated,
    dt_started AS dt_absence_started,
    dt_ended AS dt_absence_ended,
    ts_approved,
    NOW() AS ts_load,
  ROW_NUMBER() OVER (PARTITION BY id_per_absence_entry ORDER BY object_version_number DESC) AS _rn
FROM
    datalake_pin_absence_clean.person_entry
)
WHERE _rn = 1