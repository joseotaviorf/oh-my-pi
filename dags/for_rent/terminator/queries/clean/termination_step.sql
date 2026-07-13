SELECT
    id,
    termination_id AS id_termination,
    step,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_terminator_raw.termination_step
