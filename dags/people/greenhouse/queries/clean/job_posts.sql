SELECT
    -- ids
    id,
    job_id AS id_job,
    demographic_question_set_id AS id_demographic_question_set,
    -- text fields
    title,
    location.name AS location_name,
    content AS content_html,
    internal_content AS internal_content_html,
    -- boolean
    CAST(active AS BOOLEAN) AS is_active,
    CAST(live AS BOOLEAN) AS is_live,
    CAST(internal AS BOOLEAN) AS is_internal,
    CAST(external AS BOOLEAN) AS is_external,
    -- timestamps
    CAST(first_published_at AS TIMESTAMP) AS ts_first_published,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    NOW() AS ts_load,
    -- arrays
    questions,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.job_posts
WHERE
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')