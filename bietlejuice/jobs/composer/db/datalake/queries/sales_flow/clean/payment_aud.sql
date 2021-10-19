SELECT
    id,
    sales_flow_id AS id_sales_flow,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    payment_method,
    payment_model,
    total,
    deposit,
    entry,
    fgts,
    financing,
    brokerage,
    status,
    sales_flow_id_mod AS mod_id_sales_flow,
    payment_method_mod AS mod_payment_method,
    payment_model_mod AS mod_payment_model,
    total_mod AS mod_total,
    deposit_mod AS mod_deposit,
    entry_mod AS mod_entry,
    fgts_mod AS mod_fgts,
    financing_mod AS mod_financing,
    brokerage_mod AS mod_brokerage,
    status_mod AS mod_status,
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