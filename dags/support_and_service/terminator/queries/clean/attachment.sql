SELECT
    id,
    termination_id AS id_termination,
    filename,
    path,
    type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_raw.attachment
