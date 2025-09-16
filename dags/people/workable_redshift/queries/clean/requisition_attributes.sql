SELECT
    -- ids
    id,
    requisition_template_id AS id_requisition_template,

    -- non-metrics
    position,

    -- metrics (booleans)
    enabled AS is_enabled,

    -- timestamps
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.requisition_attributes