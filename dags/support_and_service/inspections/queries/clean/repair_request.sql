SELECT
    id AS id_repair_request,
    reviewer_id AS id_reviewer,
    main_id AS id_main,
    item_group_id AS id_item_group,
    granted_by_id AS id_granted_by,
    responsibility,
    uuid,
    type,
    comment,
    exempted AS is_exempted,
    from_analysis AS is_from_analysis,
    granted_at AS ts_granted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.repair_request
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}