SELECT
    id,
    case_id AS id_case,
    correlation_id AS id_correlation,
    external_id AS id_external,
    body,
    context_fields,
    customer,
    origin,
    priority,
    status,
    task_manager,
    type,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    last_external_update_at AS ts_external_updated,
    year,
    month,
    day
FROM
    datalake_taskmaster_test_raw.task
