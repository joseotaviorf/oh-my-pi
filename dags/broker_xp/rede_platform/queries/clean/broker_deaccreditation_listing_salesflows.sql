SELECT
    id,
    process_uuid AS uuid_process,
    house_id AS id_house,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rede_platform_raw.broker_deaccreditation_listing_salesflows