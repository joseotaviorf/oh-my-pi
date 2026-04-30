SELECT
    id AS id_repair_city,
    repair_city_group_id AS id_repair_city_group,
    city_region_id AS id_city_region,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.repair_city
