SELECT *
FROM
    dataset
WHERE
    updated_at >= DATE('{load_start_date}')
    AND updated_at <= (DATE('{load_end_date}') + 1)
