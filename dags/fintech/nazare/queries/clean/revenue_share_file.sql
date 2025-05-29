SELECT
    BIGINT(`id`) AS id_file,
    file_path,
    entity,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(imported_at) AS ts_imported
FROM
    datalake_nazare_raw.revenue_share_file
