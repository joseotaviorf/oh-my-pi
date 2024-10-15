SELECT
    id,
    item_group_type_id AS id_item_group_type,
    repair_suggestion_id AS id_repair_suggestion,
    previous_item_type_id AS id_previous_item_type,
    current_item_type_id AS id_current_item_type,
    previous_item_issue_type_id AS id_previous_item_issue_type,
    current_item_issue_type_id AS id_current_item_issue_type,
    item_group_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.item_group_state
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
