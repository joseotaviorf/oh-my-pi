SELECT
    id,
    application_id AS id_application,
    job_interview_id AS id_job_interview,
    job_id AS id_job,
    organizer_id AS id_organizer,
    external_event_id AS id_external_event,
    status,
    location,
    video_conferencing_url,
    CAST(starts_at AS TIMESTAMP) AS ts_started,
    CAST(ends_at AS TIMESTAMP) AS ts_ended,
    CAST(scheduled_at AS TIMESTAMP) AS ts_scheduled,
    CAST(availability_received_at AS TIMESTAMP) AS ts_availability_received,
    CAST(all_day_start_on AS DATE) AS dt_all_day_started,
    CAST(all_day_end_on AS DATE) AS dt_all_day_ended,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.interviews
WHERE
    MAKE_DATE(year, month, day) >= DATE('{load_start_date}')
    AND MAKE_DATE(year, month, day) < DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY
            CAST(updated_at AS TIMESTAMP) DESC NULLS LAST,
            CAST(created_at AS TIMESTAMP) DESC NULLS LAST,
            year DESC,
            month DESC,
            day DESC
    ) = 1
