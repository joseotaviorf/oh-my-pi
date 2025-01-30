SELECT
    id,
    sales_flow_id AS id_sales_flow,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    opportunities_of_the_week,
    isolve_link,
    google_drive_link,
    isolve_link_mod AS mod_isolve_link,
    google_drive_link_mod AS mod_google_drive_link,
    sales_flow_id_mod AS mod_id_sales_flow,
    opportunities_of_the_week_mod AS mod_opportunities_of_the_week,
    seller_fup_at_mod AS mod_ts_seller_fup,
    buyer_fup_at_mod AS mod_ts_buyer_fup,
    seller_fup_at AS ts_seller_fup,
    buyer_fup_at AS ts_buyer_fup,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.sales_flow_details_aud