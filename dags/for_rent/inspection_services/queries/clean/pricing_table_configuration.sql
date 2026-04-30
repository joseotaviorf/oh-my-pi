SELECT
    id AS id_pricing_table_configuration,
    config_version,
    approver,
    approval_url,
    version,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.pricing_table_configuration
