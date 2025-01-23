SELECT
    id,
    unit_id AS id_unit,
    user_id AS id_user,
    crawlergroup_id AS id_crawler_group,
    assignment_id AS id_assignment,
    suggested_document_id AS id_suggested_document,
    operation_id AS id_operation,
    type,
    document_crawler_type,
    status,
    filename AS file_name,
    document_filepath AS document_file_path,
    document_file,
    obs,
    description,
    slug,
    created_at AS ts_created,
    delivered_at AS ts_delivered
FROM
    datalake_legaut_test_raw.meuSite_document
