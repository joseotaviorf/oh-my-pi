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
    datalake_sales_flow_test_raw.status