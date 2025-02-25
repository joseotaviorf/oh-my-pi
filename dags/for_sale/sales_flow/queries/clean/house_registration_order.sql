SELECT
    id,
    external_house_id AS id_house_external,
    house_registration_number,
    city,
    state,
    registry_office,
    status,
    order_number,
    error_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.house_registration_order

