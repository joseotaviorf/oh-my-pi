SELECT
    -- ids
    id,

    -- non-metrics
    disabled_custom_attributes,
    app_form,
    profile,

    -- timestamps
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.custom_attributes_settings