SELECT
    -- ids
    id,
    candidate_id AS id_candidate,
    location_id AS id_location,

    -- non-metrics
    section_title,
    question_title,
    description,

    -- metrics
    CAST(responses_count AS BIGINT) AS responses_count,
    enabled AS is_enabled,

    -- timestamps
    TO_TIMESTAMP(submitted_at) AS ts_submitted,
    TO_TIMESTAMP(published_at) AS ts_published,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.surveys