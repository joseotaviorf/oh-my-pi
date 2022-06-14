SELECT
    id,
    buyer_id AS id_buyer,
    seller_id AS id_seller,
    house_id AS id_house,
    monday_id AS id_monday,
    closing_type_id AS id_closing_type,
    flow_step,
    flow_type,
    status_closing,
    status,
    closing_canceled_reason,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    is_canceled,
    buyer_id_mod AS mod_id_buyer,
    seller_id_mod AS mod_id_seller,
    house_id_mod AS mod_id_house,
    monday_id_mod AS mod_id_monday,
    closing_type_id_mod AS mod_id_closing_type,
    flow_step_mod AS mod_flow_step,
    flow_type_mod AS mod_flow_type,
    status_closing_mod AS mod_status_closing,
    status_mod AS mod_status,
    closing_canceled_reason_mod AS mod_closing_canceled_reason,
    is_canceled_mod AS mod_is_canceled,
    canceled_at AS ts_canceled, 
    canceled_at_mod AS ts_canceled_mod, 
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
