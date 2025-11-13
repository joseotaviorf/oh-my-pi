SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    investor,
    investor_mod AS mod_investor,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.buyer_app_data_aud
