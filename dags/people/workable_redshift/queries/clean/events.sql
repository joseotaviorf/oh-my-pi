SELECT
    -- ids
    id,
    candidate_id AS id_candidate,
    organizer_id AS id_organizer,
    stage_id AS id_stage,

    -- non-metrics
    candidate_name,
    type,
    title,
    location,
    organizer_name,
    stage_name,
    language,

    -- metrics
    CAST(cancelled AS BOOLEAN) AS is_cancelled,

    -- timestamps
    TO_TIMESTAMP(event_created_at) AS ts_event_created,
    TO_TIMESTAMP(starts_at) AS ts_started,
    TO_TIMESTAMP(ends_at) AS ts_ended,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.events