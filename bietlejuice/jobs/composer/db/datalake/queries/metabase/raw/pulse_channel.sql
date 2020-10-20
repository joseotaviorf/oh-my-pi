SELECT
    id,
    pulse_id,
    channel_type,
    details,
    schedule_type,
    schedule_frame,
    schedule_hour,
    schedule_day,
    enabled,
    created_at,
    updated_at,
    EXTRACT(year FROM updated_at)::INT AS year,
    EXTRACT(month FROM updated_at)::INT AS month,
    EXTRACT(day FROM updated_at)::INT AS day
FROM
    metabase."pulse_channel"
WHERE 
    EXTRACT(year FROM updated_at) = {year}
    AND EXTRACT(month FROM updated_at) = {month}
    AND EXTRACT(day FROM updated_at) = {day}