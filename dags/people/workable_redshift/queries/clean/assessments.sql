SELECT
    -- ids
    candidate_id AS id_candidate,
    assessment_id AS id_assessment,
    stage_id AS id_stage,

    -- non-metrics
    name,
    provider_name,
    provider_slug,
    provider_type,
    results,
    meta,

    -- metrics
    CAST(overall_score AS DECIMAL(10, 2)) AS overall_score,

    -- timestamps
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.assessments