SELECT
    id,
    external_id AS id_external,
    address_data_id AS id_address_data,
    land_tenure,
    house_registration_status,
    has_seller_debt_payments,
    has_chattel_mortgage,
    registry_must_be_updated AS has_pending_registry_update,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.house
