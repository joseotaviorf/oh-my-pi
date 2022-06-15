SELECT
    id,
    crawler_id AS id_crawler,
    crawlergroup_id AS id_crawler_group,
    unit_id AS id_unit,
    document_id AS id_document,
    storages_path,
    status,
    type,
    result,
    run_start AS ts_run_start,
    run_end AS ts_run_end
FROM
    datalake_legaut_raw.crawlers_crawler
