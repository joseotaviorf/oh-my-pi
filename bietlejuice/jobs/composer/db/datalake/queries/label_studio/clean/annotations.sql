SELECT
    CAST(id AS BIGINT) AS id_annotation,
    project_name,
    created_username,
    created_ago,
    completed_by,
    task,
    result,
    CAST(lead_time AS FLOAT) AS lead_time,
    was_cancelled AS is_cancelled,
    ground_truth AS is_ground_truth,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated
FROM
    datalake_label_studio_raw.label_studio