SELECT
    id AS id_ccv_flow_aud,
    sales_flow_id AS id_sales_flow,
    status,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    is_5a_model,
    sales_flow_id_mod AS mod_id_sales_flow,
    status_mod AS mod_status,
    started_confection_at_mod AS mod_ts_confection_started,
    is_5a_model_mod AS mod_is_5a_model,
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
