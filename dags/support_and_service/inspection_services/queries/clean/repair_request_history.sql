SELECT
    id,
    repair_request_id AS id_repair_request,
    reviewer_id AS id_reviewer,
    granted_by_id AS id_granted_by,
    last_reviewer_id AS id_last_reviewer,
    uuid,
    cost,
    title,
    origin,
    repair_service,
    type,
    comment,
    responsibility,
    from_analysis is_from_analysis,
    exempted AS is_exempted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.repair_request_history
