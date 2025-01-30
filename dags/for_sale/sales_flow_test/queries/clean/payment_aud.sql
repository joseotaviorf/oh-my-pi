SELECT
    id,
    sales_flow_id AS id_sales_flow,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    payment_method,
    payment_model,
    down_payment_value,
    entry_amount,
    fgts_value
    status,
    sales_flow_id_mod AS mod_id_sales_flow,
    payment_method_mod AS mod_payment_method,
    payment_model_mod AS mod_payment_model,
    down_payment_value_mod AS mod_down_payment_value,
    entry_amount_mod AS mod_entry_amount,
    fgts_value_mod AS mod_fgts_value,
    status_mod AS mod_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.payment_aud