SELECT
    id AS id_repair_request_media,
    repair_request_id AS id_repair_request,
    main_id AS id_main,
    uuid,
    type,
    name,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.repair_request_media rrm
