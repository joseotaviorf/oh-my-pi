SELECT
    id,
    crawler_id AS id_crawler,
    crawlergroup_id AS id_crawler_group,
    unit_id AS id_unit,
    document_id AS id_document,
    error_code,
    manual_reason,
    storages_path,
    rerun_tries,
    status,
    type_id AS type,
    result,
    deleted AS ts_run_deleted,
    run_start AS ts_run_start,
    run_end AS ts_run_end
FROM
    datalake_legaut_test_raw.crawlers_crawler
