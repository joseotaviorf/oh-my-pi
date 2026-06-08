SELECT
    id AS id_repair_analysis,
    inspection_id AS id_inspection,
    pricing_table_configuration_id AS id_pricing_table_configuration,
    region AS id_region,
    status,
    property_area,
    rent_value,
    city_group_multiplier,
    rent_multiplier,
    charged_repairs_total,
    automatically_priced_repairs_count,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.repair_analysis
