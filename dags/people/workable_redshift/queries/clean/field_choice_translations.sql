SELECT
    -- ids
    id,
    field_choice_id AS id_field_choice,

    -- non-metrics
    label,
    language,

    -- timestamps
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.field_choice_translations