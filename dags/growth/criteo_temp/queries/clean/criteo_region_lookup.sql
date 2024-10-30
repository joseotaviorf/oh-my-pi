SELECT 
    postcode_range,
    start_range::STRING,
    end_range::STRING,
    state,
    locality
FROM
    datalake_gsheets_raw.criteo_region_lookup