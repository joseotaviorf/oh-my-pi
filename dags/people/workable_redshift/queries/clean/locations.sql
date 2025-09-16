SELECT
    -- ids
    id,

    -- non-metrics
    country_code,
    state_code,
    city,
    subregion,
    zip_code,
    location_string,
    coords,

    -- timestamps
    TO_TIMESTAMP(location_created_at) AS ts_location_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.locations