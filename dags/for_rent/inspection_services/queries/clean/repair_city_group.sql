SELECT
    id AS id_repair_city_group,
    pricing_table_configuration_id AS id_pricing_table_configuration,
    name,
    rate,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.repair_city_group
