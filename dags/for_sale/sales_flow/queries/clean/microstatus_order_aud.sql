SELECT
    id,
    status_order_id AS id_status_order,
    status_id AS id_status,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    ordering,
    status_order_id_mod AS mod_id_status_order,
    status_id_mod AS mod_id_status,
    ordering_mod AS mod_ordering,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.microstatus_order_aud

