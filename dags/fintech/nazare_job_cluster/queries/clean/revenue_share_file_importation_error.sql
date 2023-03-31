SELECT
    `id` AS id_importation_error,
    `file_id` AS id_file,
    `error_message` AS error_description,
    original_value AS json_error_values,
    created_at AS ts_created
FROM
    datalake_nazare_job_cluster_raw.revenue_share_file_importation_error
