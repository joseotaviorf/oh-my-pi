SELECT
    id AS id_repair_request,
    reviewer_id AS id_reviewer,
    main_id AS id_main,
    item_group_id AS id_item_group,
    granted_by_id AS id_granted_by,
    repair_suggestion_id AS id_repair_suggestion,
    responsibility,
    uuid,
    type,
    comment,
    repair_service,
    title,
    cost,
    exempted AS is_exempted,
    exempted_from_budget AS is_exempted_from_budget,
    from_analysis AS is_from_analysis,
    finished AS is_finished,
    automatically_identified AS has_automatically_identified,
    automatic_identification_accepted AS has_automatic_identification_accepted,
    granted_at AS ts_granted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.repair_request
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
