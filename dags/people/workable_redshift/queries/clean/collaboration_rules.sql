SELECT
    -- ids
    id,
    member_id AS id_member,

    -- non-metrics
    role,
    country_code,
    state_code,
    city,
    subregion,
    zip_code,

    -- timestamps
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.collaboration_rules
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)