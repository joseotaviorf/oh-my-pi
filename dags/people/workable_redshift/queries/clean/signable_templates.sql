SELECT
    -- ids
    id,

    -- non-metrics
    type,
    name,
    email_body,
    language,
    country_code,
    state_code,
    city,
    subregion,
    zip_code,

    -- timestamps
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.signable_templates