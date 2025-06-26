SELECT
    MD5(approval_status_code) AS sk_request_status,
    approval_status_code AS request_status_name,
    NOW() AS ts_load
FROM
    datalake_pin_absence_clean.person_entry
WHERE
    approval_status_code IS NOT NULL
GROUP BY
    approval_status_code