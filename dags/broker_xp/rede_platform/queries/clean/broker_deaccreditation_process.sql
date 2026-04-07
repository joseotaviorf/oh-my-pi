SELECT
    id,
    process_uuid AS uuid_process,
    company_uuid AS uuid_company,
    product_uuid AS uuid_product,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    completed_at AS ts_completed,
    year,
    month,
    day
FROM
    datalake_rede_platform_raw.broker_deaccreditation_process