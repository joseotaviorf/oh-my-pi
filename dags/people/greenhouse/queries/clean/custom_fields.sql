SELECT
    -- ids
    id,
    -- text fields
    name,
    field_type,
    value_type,
    name_key,
    description,
    template_token_string,
    -- numeric
    priority,
    -- boolean
    CAST(active AS BOOLEAN) AS is_active,
    CAST(private AS BOOLEAN) AS is_private,
    CAST(required AS BOOLEAN) AS is_required,
    CAST(require_approval AS BOOLEAN) AS is_approval_required,
    CAST(trigger_new_version AS BOOLEAN) AS is_new_version_trigger,
    CAST(expose_in_job_board_api AS BOOLEAN) AS is_exposed_in_job_board_api,
    CAST(api_only AS BOOLEAN) AS is_api_only,
    -- timestamps
    NOW() AS ts_load,
    -- arrays
    offices,
    departments,
    custom_field_options,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.custom_fields