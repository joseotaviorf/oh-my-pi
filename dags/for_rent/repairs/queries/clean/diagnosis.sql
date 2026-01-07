SELECT
    id,
    repair_expense_id AS id_repair_expense,
    name,
    content,
    criticality,
    responsibility,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_repairs_raw.diagnosis
