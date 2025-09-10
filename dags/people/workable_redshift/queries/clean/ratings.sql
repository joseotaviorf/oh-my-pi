SELECT
    -- ids
    id,
    candidate_id AS id_candidate,
    stage_id AS id_stage,
    member_id AS id_member,

    -- non-metrics
    scale,
    score_card,

    -- metrics
    CAST(score AS DECIMAL(10, 2)) AS score,

    -- timestamps
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.ratings