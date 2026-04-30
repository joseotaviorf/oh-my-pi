SELECT
    id AS id_item_price,
    pricing_table_configuration_id AS id_pricing_table_configuration,
    item_group_type_id AS id_item_group_type,
    item_group_specification_id AS id_item_group_specification,
    repair_service,
    price_amount,
    price_currency,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.item_price
