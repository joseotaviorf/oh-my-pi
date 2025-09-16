SELECT
    -- ids
    id,
    posting_id AS id_posting,

    -- non-metrics
    values,

    -- timestamps
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.extra_infos