SELECT
    -- ids
    id AS id_rejection_detail,
    application_id AS id_application,
    rejected_by_id AS id_rejected_by,
    rejection_note_id AS id_rejection_note,
    rejection_reason_id AS id_rejection_reason,
    -- timestamps
    CAST(rejected_at AS TIMESTAMP) AS ts_rejected,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- structs
    question_custom_fields,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.rejection_details
