SELECT
    id,
    sales_flow_id AS id_sales_flow,
    opportunities_of_the_week,
    isolve_link,
    google_drive_link,
    seller_fup_at AS ts_seller_fup,
    buyer_fup_at AS ts_buyer_fup,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.sales_flow_details