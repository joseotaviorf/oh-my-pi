SELECT
    -- ids
    id,

    -- non-metrics
    visibility_mask AS code_visibility_mask,
    hint,
    provider,

    -- metrics (booleans)
    CAST(single_answer AS BOOLEAN) AS is_single_answer,
    CAST(enabled AS BOOLEAN) AS is_enabled,

    -- timestamps
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.custom_attributes