SELECT
    -- ids
    id,
    job_id AS id_job,

    -- non-metrics
    job_title,
    job_board,
    type,
    url,
    state,

    -- metrics
    CAST(max_duration AS BIGINT) AS max_duration,
    CAST(price AS DECIMAL(18, 2)) AS price,
    CAST(days_published AS BIGINT) AS days_published,
    CAST(candidates_count AS BIGINT) AS candidates_count,

    -- timestamps
    TO_TIMESTAMP(posting_created_at) AS ts_posting_created,
    TO_TIMESTAMP(published_at) AS ts_published,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.postings