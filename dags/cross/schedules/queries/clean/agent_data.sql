SELECT
    id,
    calendar_id AS id_calendar,
    displacement_profile,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_schedules_raw.agent_data
