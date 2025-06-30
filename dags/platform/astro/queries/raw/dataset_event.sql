SELECT *
FROM
    dataset_event
WHERE
    timestamp >= DATE('{load_start_date}')
    AND timestamp <= (DATE('{load_end_date}') + 1)
