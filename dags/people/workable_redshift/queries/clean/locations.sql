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
    TO_JSON(coords) AS coords,

    -- timestamps
    TO_TIMESTAMP(location_created_at) AS ts_location_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.locations
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)