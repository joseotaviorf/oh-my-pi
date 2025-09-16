SELECT
    -- ids
    id,
    candidate_id AS id_candidate,
    job_id AS id_job,
    member_id AS id_member,

    -- non-metrics
    name,
    title,
    member_name,
    body,

    -- timestamps
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.comments