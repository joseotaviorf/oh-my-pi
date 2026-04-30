SELECT
    id AS id_rent_value_rate,
    pricing_table_configuration_id AS id_pricing_table_configuration,
    from_value,
    to_value,
    rate,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.rent_value_rate
