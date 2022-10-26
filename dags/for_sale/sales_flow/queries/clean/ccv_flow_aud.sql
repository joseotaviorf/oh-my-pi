SELECT
    id AS id_ccv_flow_aud,
    sales_flow_id AS id_sales_flow,
    status,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    sales_flow_id_mod AS mod_id_sales_flow,
    status_mod AS mod_status,
    started_confection_at_mod AS mod_ts_confection_started,
    signed_at_mod AS mod_ts_signed,
    started_confection_at AS ts_confection_started,
    signed_at AS ts_signed,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_flow_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}