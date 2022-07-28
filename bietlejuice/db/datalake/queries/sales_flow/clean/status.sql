SELECT
    id,
    label_id AS id_label,
    parent_id AS id_parent,
    key,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.status
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
