SELECT
    id,
    name,
    description,
    start_date AS ts_started,
    end_date AS ts_ended
FROM
    datalake_sorting_hat_raw.`experiment`
