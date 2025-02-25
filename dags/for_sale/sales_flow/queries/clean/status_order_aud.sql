SELECT
    id,
    closing_type_id AS id_closing_type,
    status_id AS id_status,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    ordering,
    closing_type_id_mod AS mod_id_closing_type,
    status_id_mod AS mod_id_status,
    ordering_mod AS mod_ordering,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.status_order_aud

