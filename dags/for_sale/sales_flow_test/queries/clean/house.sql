SELECT
    id,
    external_id AS id_external,
    address_data_id AS id_address_data,
    land_tenure,
    house_registration_status,
    has_seller_debt_payments,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.house