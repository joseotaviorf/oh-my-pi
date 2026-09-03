SELECT
    external_id AS id_external,
    calendar_id AS id_calendar,
    identity_source,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_schedules_raw.external_reference
