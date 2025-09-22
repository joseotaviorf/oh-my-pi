SELECT
    -- ids
    id,
    application_id AS id_application,
    interview.id AS id_interview,
    organizer.id AS id_organizer,
    external_event_id AS id_external_event,
    -- text fields
    status,
    video_conferencing_url,
    interview.name AS interview_name,
    organizer.name AS organizer_name,
    -- timestamps
    CAST(start.date_time AS TIMESTAMP) AS ts_started,
    CAST(end.date_time AS TIMESTAMP) AS ts_ended,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- arrays
    TRANSFORM(
        interviewers,
        interviewer -> STRUCT(
            interviewer.id,
            interviewer.name,
            interviewer.email,
            interviewer.response_status,
            interviewer.scorecard_id
        )
    ) AS interviewers,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.scheduled_interviews