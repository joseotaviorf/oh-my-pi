SELECT
    id,
    task_id AS id_task,
    parent_annotation_id AS id_parent_annotation,
    parent_prediction_id AS id_parent_prediction,
    completed_by_id AS id_completed_by,
    last_created_by_id AS id_last_created_by,
    prediction,
    lead_time,
    result_count,
    last_action,
    ground_truth AS is_ground_truth,
    was_cancelled,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_quinturk_raw.task_completion
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
