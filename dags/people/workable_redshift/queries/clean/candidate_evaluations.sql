SELECT
    -- ids
    id,
    candidate_id AS id_candidate,
    stage_id AS id_stage,
    member_id AS id_member,

    -- non-metrics
    candidate_name,
    stage_name,
    member_name,

    -- metrics
    CAST(score AS DECIMAL(10, 2)) AS score,

    -- timestamps
    TO_TIMESTAMP(evaluation_created_at) AS ts_evaluation_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.candidate_evaluations
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)