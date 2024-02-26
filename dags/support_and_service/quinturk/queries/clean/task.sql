SELECT
    id,
    project_id AS id_project,
    updated_by_id AS id_updated_by,
    file_upload_id AS id_file_upload,
    inner_id AS id_inner,
    total_annotations,
    canceled_annotations,
    total_predictions,
    overlap,
    data,
    meta,
    is_labeled,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_quinturk_raw.task
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
