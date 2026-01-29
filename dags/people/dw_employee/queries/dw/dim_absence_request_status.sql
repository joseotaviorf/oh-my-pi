WITH status_combinations AS (
    SELECT DISTINCT
        approval_status_code, 
        absence_status_code
    FROM
        datalake_pin_absence_clean.person_entry
)
SELECT
    MD5(CONCAT(COALESCE(approval_status_code, ''), '|', COALESCE(absence_status_code, ''))) AS sk_absence_request_status,
    CASE
        WHEN absence_status_code = 'ORA_WITHDRAWN' THEN 'Withdrawn'
        WHEN approval_status_code = 'DENIED' THEN 'Denied'
        WHEN approval_status_code = 'APPROVED' THEN 'Approved'
        WHEN approval_status_code IN ('AWAITING', 'ORA_AWAIT_AWAIT') THEN 'Awaiting approval'
        ELSE 'In draft'
    END AS request_status,
    CASE
        WHEN approval_status_code = 'APPROVED' THEN 'Approved'
        WHEN approval_status_code = 'DENIED' THEN 'Denied'
        WHEN approval_status_code IN ('AWAITING', 'ORA_AWAIT_AWAIT') THEN 'Awaiting approval'
        WHEN approval_status_code IS NULL THEN 'In draft'
        ELSE CONCAT(approval_status_code, '*')
    END AS approval_status,
    CASE
        WHEN absence_status_code = 'SAVED' THEN 'Saved'
        WHEN absence_status_code = 'SUBMITTED' THEN 'Awaiting Approval'
        WHEN absence_status_code = 'ORA_WITHDRAWN' THEN 'Withdrawn'
        ELSE CONCAT(absence_status_code, '*')
    END AS user_request_status,
    NOW() AS ts_load
FROM
    status_combinations
