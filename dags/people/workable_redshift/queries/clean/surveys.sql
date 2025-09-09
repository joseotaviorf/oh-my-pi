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
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.surveys
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)