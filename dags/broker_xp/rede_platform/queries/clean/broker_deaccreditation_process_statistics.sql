SELECT
    id,
    process_id AS id_process,
    process_step_type,
    total,
    processed,
    failed,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rede_platform_raw.broker_deaccreditation_process_statistics