SELECT
    `id` AS id_file,
    file_path,
    entity,
    created_at AS ts_created,
    imported_at AS ts_imported
FROM
    datalake_nazare_job_cluster_raw.revenue_share_file
