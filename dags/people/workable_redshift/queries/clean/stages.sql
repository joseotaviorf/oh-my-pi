SELECT
    id,
    base_stage_id AS id_base_stage,
    pipeline_id AS id_pipeline,
    `name`,
    kind,
    `position`,
    slug,
    confidential AS is_confidential,
    stage_created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.stages
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')