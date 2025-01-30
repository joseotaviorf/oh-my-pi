SELECT
    id,
    ccv_id AS id_ccv,
    address_data_id AS id_address_data,
    type,
    name,
    email,
    document,
    nationality,
    profession,
    marital_status, 
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.ccv_party