SELECT
    id AS id_annotation,
    project_id AS id_project,
    created_username,
    created_ago,
    completed_by,
    task,
    result,
    lead_time AS lead_time,
    was_cancelled AS is_cancelled,
    ground_truth AS is_ground_truth,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated
FROM
    datalake_label_studio_raw.annotations