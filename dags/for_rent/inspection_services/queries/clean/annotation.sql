SELECT
    inspection_uuid AS uuid_inspection,
    key,
    value,
    created_by_email,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
	datalake_inspection_services_raw.annotation
