SELECT
    id,
    sales_flow_id AS id_sales_flow,
    status_id AS id_status,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    sales_flow_id_mod AS mod_id_sales_flow,
    status_id_mod AS mod_id_status,
    status_start_date_mod AS mod_ts_status_start,
    status_end_date_mod AS mod_ts_status_end,
    status_start_date AS ts_status_start,
    status_end_date AS ts_status_end,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.status_record_aud