SELECT
    id,
    pulse_id AS id_pulse,
    channel_type,
    details,
    schedule_type,
    schedule_frame,
    schedule_hour,
    schedule_day,
    enabled AS is_enabled,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_metabase_raw.pulse_channel
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}