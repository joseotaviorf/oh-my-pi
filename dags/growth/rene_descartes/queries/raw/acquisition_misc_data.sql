SELECT
    *,
    DATE(updated_at) AS dt
FROM
    acquisition_misc_data
WHERE
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')