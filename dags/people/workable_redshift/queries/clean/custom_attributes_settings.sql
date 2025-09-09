SELECT
    -- ids
    id,

    -- non-metrics
    disabled_custom_attributes,
    TO_JSON(app_form) AS app_form,
    TO_JSON(profile) AS profile,

    -- timestamps
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.custom_attributes_settings
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)