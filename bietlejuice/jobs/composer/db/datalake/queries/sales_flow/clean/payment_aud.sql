SELECT
    id,
    sales_flow_id AS id_sales_flow,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    payment_method,
    payment_model,
    sales_flow_id_mod AS mod_id_sales_flow,
    payment_method_mod AS mod_payment_method,
    payment_model_mod AS mod_payment_model,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.payment_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}