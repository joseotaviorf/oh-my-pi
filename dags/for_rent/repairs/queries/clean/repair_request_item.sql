SELECT
    id,
    expense_id AS id_expense,
    repair_request_id AS id_repair_request,
    description AS repair_item_description,
    is_urgent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_repairs_raw.repair_request_item
