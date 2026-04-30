SELECT
    id AS id_item_room_price,
    pricing_table_configuration_id AS id_pricing_table_configuration,
    room_type_id AS id_room_type,
    item_group_type_id AS id_item_group_type,
    repair_service,
    from_property_area,
    to_property_area,
    price_amount,
    price_currency,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.item_room_price
