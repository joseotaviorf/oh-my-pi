SELECT
    *,
    DATE(updated_at) AS dt
FROM
    rejection_history_event
WHERE
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')